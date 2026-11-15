param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$Host.UI.RawUI.WindowTitle = 'HentaiPark Web - starting'

# The kernel closes this job when the terminal/supervisor exits, including X.
# Only this launcher's service and its descendants belong to the job.
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public sealed class WebServiceJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Basic {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct Io {
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct Extended {
        public Basic Basic;
        public Io Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref Extended info, uint size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    IntPtr handle;
    public WebServiceJob() {
        handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        var info = new Extended(); info.Basic.Flags = 0x2000;
        if (!SetInformationJobObject(handle, 9, ref info, (uint)Marshal.SizeOf(info))) {
            Dispose(); throw new System.ComponentModel.Win32Exception();
        }
    }
    public void Attach(Process process) {
        if (!AssignProcessToJobObject(handle, process.Handle)) throw new System.ComponentModel.Win32Exception();
    }
    public void Dispose() { if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; } }
}
'@

$mutex = $null
$stopEvent = $null
$job = $null
$service = $null
$ownsMutex = $false
try {
    & node (Join-Path $PSScriptRoot 'check-env.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Environment check failed. See the error above.' }

    $sha = [Security.Cryptography.SHA256]::Create()
    try { $identity = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($projectRoot.ToLowerInvariant())))).Replace('-', '') } finally { $sha.Dispose() }
    $mutex = [Threading.Mutex]::new($false, ('Local\HentaiParkWeb-' + $identity))
    $stopEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, ('Local\HentaiParkWebStop-' + $identity))
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (!$ownsMutex) {
        Write-Host 'Stopping the previous HentaiPark Web service for this project...'
        [void]$stopEvent.Set()
        try { $ownsMutex = $mutex.WaitOne(20000) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (!$ownsMutex) { throw 'Previous launcher did not stop. No unrelated process was terminated.' }
    }
    [void]$stopEvent.Reset()
    & node (Join-Path $PSScriptRoot 'ensure-build.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Application build failed. See the error above.' }
    $job = [WebServiceJob]::new()
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    $info.WorkingDirectory = $projectRoot
    $info.Arguments = '--env-file-if-exists=.env "' + (Join-Path $PSScriptRoot 'start-web.mjs') + '" --windows-launcher'
    if (!$NoBrowser) { $info.Arguments += ' --open-browser' }
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $service = [Diagnostics.Process]::new()
    $service.StartInfo = $info
    [void]$service.Start()
    try { $job.Attach($service) } catch { if (!$service.HasExited) { $service.Kill() }; throw }
    $Host.UI.RawUI.WindowTitle = 'HentaiPark Web - service console'
    while (!$service.WaitForExit(200)) {
        if ($stopEvent.WaitOne(0)) {
            Write-Host 'Shutting down the old service...'
            $service.StandardInput.WriteLine('shutdown')
            $service.StandardInput.Flush()
            if (!$service.WaitForExit(10000)) { Write-Host 'Shutdown deadline reached; releasing the service process tree.' }
            break
        }
    }
    if ($service.HasExited -and $service.ExitCode -ne 0) { throw ('Service exited with code ' + $service.ExitCode) }
} catch {
    if ($job) { $job.Dispose(); $job = $null }
    if ($ownsMutex) { $mutex.ReleaseMutex(); $ownsMutex = $false }
    Write-Host $_.Exception.Message -ForegroundColor Red
    [void](Read-Host 'Startup failed. Press Enter to close')
} finally {
    if ($job) { $job.Dispose() }
    if ($service) { $service.Dispose() }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($stopEvent) { $stopEvent.Dispose() }
    if ($mutex) { $mutex.Dispose() }
}
