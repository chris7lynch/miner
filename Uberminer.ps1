# Originally designed for use with ethminer.?
# Lynch & Diehl
#
# To do:
#
# Ensure worker id will work for various pools - nano, ethermine etc
# Add overclock input params for clock and mem
# Add overclock settings apply
# Possibly use PS background jobs rather than execs
# allow different settings based on GPU model i.e. 1060, 1070 etc

Param(
    # Folder path to the miner exe.
    [String]$minerPath="c:\ethminer\bin",

    # Miner executable name.
    [String]$minerExe="ethminer.exe",

    # Worker name, defaults to the computer name.  Will auto-append the GPU number if using multiple GPUs.
    [String]$workerName = $env:computername,

    # Your Ethereum Account Number.
    [String]$etherAcct = "0x96ae82e89ff22b3eff481e2499948c562354cb23",

    # The pool address to mine in.
    [String]$poolUrl = "eth-us-west1.nanopool.org:9999",

    # Additional arguments, defaults should suffice but can be changed if desired.
    [String]$addlArgs = "--cuda-parallel-hash 4",

    # Time in seconds to wait before checking GPU usage for all miners.
    [Int]$checkup = 30,

    # Minimum CPU usage to check for when deciding if the miner is fucntioning.
    [Int]$minGpuUse = 80
)

# Global object to store GPU# and corresponding PID
$Global:ledger = New-Object PSObject

Function getGpuUse([string]$gpuId) {
    # path to nvsmi exe
    Set-Location "C:\Program Files\NVIDIA Corporation\NVSMI"
    $util = .\nvidia-smi.exe --query-gpu="utilization.gpu" --format="csv,noheader,nounits" --id="$gpuId"
    [int]$intUtil = $util
    return $intUtil
}

Function goDig($gpuId) {
    $proc = Start-Process -FilePath $minerPath/$minerExe -ArgumentList "-U -S $poolUrl -O $etherAcct.$workerName.$gpuId  --cuda-devices $gpuId $addlArgs" -Passthru
    return $proc.Id
}

Function getGpus() {
    Set-Location "C:\Program Files\NVIDIA Corporation\NVSMI"
    $objGpus = .\nvidia-smi.exe -L
    $gpus = @()
    $objGpus | ForEach-Object { $gpus += $_.substring(4,1) }
    return $gpus
}

Function watcher() {
    $gpus = getGpus
    $gpus | ForEach-Object {
        $myPid = goDig($_)
        $Global:ledger | Add-Member NoteProperty GPUID $_
        $Global:ledger | Add-Member NoteProperty PID $myPid

    }

   # Loop runs forever, killing and restarting the mining process on this GPU if GPU usage drops below threshold.
    while ($true) {
        Start-Sleep $checkup
        $Global:ledger | ForEach-Object {
            $gpuPerc = getGpuUse("$($_.GPUID)")
            $minerPid = $_.PID
            if ($gpuPerc -lt $minGpuUse) {
                Write-Host "GPU $($_.GPUID) usage is only $gpuPerc!"
                Write-Host "PID::$minerPid"
                $testRunning = Get-Process -Id $minerPid  -ErrorAction SilentlyContinue
                if($testRunning -eq $null) {
                    Write-host "Not running, starting a new miner."
                } else {
                    Start-Sleep -Seconds 10
                    if ($gpuPerc -lt $minGpuUse) {
                        Write-Host "GPU $($_.GPUID) usage is still only $gpuPerc!"
                        Write-Host "PID::$minerPid"
                        Write-host "Killing Miner.."
                        Stop-Process -Id $minerPid -Force -ErrorAction SilentlyContinue
                        Wait-Process -Id $minerPid
                    } else { Write-host "False alarm, miner is back to work..." }
                }
                $Global:ledger.PID = goDig($_.GPUID)
            } else {
                Write-Host "GPU $g usage looking good at $gpuPerc, carry on."
            }
        }
    }
}

# Start mining!
watcher