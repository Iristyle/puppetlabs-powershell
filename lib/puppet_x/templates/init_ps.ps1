[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [String]
  $InitReadyEventName,

  [Parameter(Mandatory = $true)]
  [String]
  $NamedPipeName
)

$hostSource = @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
using System.Text;
using System.Threading;

namespace Puppet
{
  public class PuppetPSHostRawUserInterface : PSHostRawUserInterface
  {
    public PuppetPSHostRawUserInterface()
    {
      buffersize      = new Size(120, 120);
      backgroundcolor = ConsoleColor.Black;
      foregroundcolor = ConsoleColor.White;
      cursorposition  = new Coordinates(0, 0);
      cursorsize      = 1;
    }

    private ConsoleColor backgroundcolor;
    public override ConsoleColor BackgroundColor
    {
      get { return backgroundcolor; }
      set { backgroundcolor = value; }
    }

    private Size buffersize;
    public override Size BufferSize
    {
      get { return buffersize; }
      set { buffersize = value; }
    }

    private Coordinates cursorposition;
    public override Coordinates CursorPosition
    {
      get { return cursorposition; }
      set { cursorposition = value; }
    }

    private int cursorsize;
    public override int CursorSize
    {
      get { return cursorsize; }
      set { cursorsize = value; }
    }

    private ConsoleColor foregroundcolor;
    public override ConsoleColor ForegroundColor
    {
      get { return foregroundcolor; }
      set { foregroundcolor = value; }
    }

    private Coordinates windowposition;
    public override Coordinates WindowPosition
    {
      get { return windowposition; }
      set { windowposition = value; }
    }

    private Size windowsize;
    public override Size WindowSize
    {
      get { return windowsize; }
      set { windowsize = value; }
    }

    private string windowtitle;
    public override string WindowTitle
    {
      get { return windowtitle; }
      set { windowtitle = value; }
    }

    public override bool KeyAvailable
    {
        get { return false; }
    }

    public override Size MaxPhysicalWindowSize
    {
        get { return new Size(165, 66); }
    }

    public override Size MaxWindowSize
    {
        get { return new Size(165, 66); }
    }

    public override void FlushInputBuffer()
    {
      throw new NotImplementedException();
    }

    public override BufferCell[,] GetBufferContents(Rectangle rectangle)
    {
      throw new NotImplementedException();
    }

    public override KeyInfo ReadKey(ReadKeyOptions options)
    {
      throw new NotImplementedException();
    }

    public override void ScrollBufferContents(Rectangle source, Coordinates destination, Rectangle clip, BufferCell fill)
    {
      throw new NotImplementedException();
    }

    public override void SetBufferContents(Rectangle rectangle, BufferCell fill)
    {
      throw new NotImplementedException();
    }

    public override void SetBufferContents(Coordinates origin, BufferCell[,] contents)
    {
      throw new NotImplementedException();
    }
  }

  public class PuppetPSHostUserInterface : PSHostUserInterface
  {
    private PuppetPSHostRawUserInterface _rawui;
    private StringBuilder _sb;

    public PuppetPSHostUserInterface()
    {
      _sb = new StringBuilder();
    }

    public override PSHostRawUserInterface RawUI
    {
      get
      {
        if ( _rawui == null){
          _rawui = new PuppetPSHostRawUserInterface();
        }
        return _rawui;
      }
    }

    public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
    {
      _sb.Append(value);
    }

    public override void Write(string value)
    {
      _sb.Append(value);
    }

    public override void WriteDebugLine(string message)
    {
      _sb.AppendLine("DEBUG: " + message);
    }

    public override void WriteErrorLine(string value)
    {
      _sb.AppendLine(value);
    }

    public override void WriteLine(string value)
    {
      _sb.AppendLine(value);
    }

    public override void WriteVerboseLine(string message)
    {
      _sb.AppendLine("VERBOSE: " + message);
    }

    public override void WriteWarningLine(string message)
    {
      _sb.AppendLine("WARNING: " + message);
    }

    public override void WriteProgress(long sourceId, ProgressRecord record)
    {
    }

    public string Output
    {
      get
      {
        string text = _sb.ToString();
        _sb = new StringBuilder();
        return text;
      }
    }

    public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
    {
      throw new NotImplementedException();
    }

    public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
    {
      throw new NotImplementedException();
    }

    public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
    {
      throw new NotImplementedException();
    }

    public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
    {
      throw new NotImplementedException();
    }

    public override string ReadLine()
    {
      throw new NotImplementedException();
    }

    public override SecureString ReadLineAsSecureString()
    {
      throw new NotImplementedException();
    }
  }

  public class PuppetPSHost : PSHost
  {
    private Guid _hostId = Guid.NewGuid();
    private bool shouldExit;
    private int exitCode;

    private readonly PuppetPSHostUserInterface _ui = new PuppetPSHostUserInterface();

    public PuppetPSHost () {}

    public bool ShouldExit { get { return this.shouldExit; } }
    public int ExitCode { get { return this.exitCode; } }
    public void ResetExitStatus()
    {
      this.exitCode = 0;
      this.shouldExit = false;
    }

    public override Guid InstanceId { get { return _hostId; } }
    public override string Name { get { return "PuppetPSHost"; } }
    public override Version Version { get { return new Version(1, 1); } }
    public override PSHostUserInterface UI
    {
      get { return _ui; }
    }
    public override CultureInfo CurrentCulture
    {
        get { return Thread.CurrentThread.CurrentCulture; }
    }
    public override CultureInfo CurrentUICulture
    {
        get { return Thread.CurrentThread.CurrentUICulture; }
    }

    public override void EnterNestedPrompt() { throw new NotImplementedException(); }
    public override void ExitNestedPrompt() { throw new NotImplementedException(); }
    public override void NotifyBeginApplication() { return; }
    public override void NotifyEndApplication() { return; }

    public override void SetShouldExit(int exitCode)
    {
      this.shouldExit = true;
      this.exitCode = exitCode;
    }
  }
}
"@

function New-XmlResult
{
  param(
    [Parameter()]$exitcode,
    [Parameter()]$output,
    [Parameter()]$errormessage
  )

  # we make our own xml because ConvertTo-Xml makes hard to parse xml ruby side
  # and we need to be sure
  $xml = [xml]@"
<ReturnResult>
  <Property Name='exitcode'>$($exitcode)</Property>
  <Property Name='errormessage'>$([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$errormessage)))</Property>
  <Property Name='stdout'>$([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$output)))</Property>
</ReturnResult>
"@
  $xml.OuterXml
}

Add-Type -TypeDefinition $hostSource -Language CSharp

#this is a string so we can import into our dynamic PS instance
$global:ourFunctions = @'
function Get-ProcessEnvironmentVariables
{
  $processVars = [Environment]::GetEnvironmentVariables('Process').Keys |
    % -Begin { $h = @{} } -Process { $h.$_ = (Get-Item Env:\$_).Value } -End { $h }

  # eliminate Machine / User vars so that we have only process vars
  'Machine', 'User' |
    % { [Environment]::GetEnvironmentVariables($_).GetEnumerator() } |
    ? { $processVars.ContainsKey($_.Name) -and ($processVars[$_.Name] -eq $_.Value) } |
    % { $processVars.Remove($_.Name) }

  $processVars.GetEnumerator() | Sort-Object Name
}

function Reset-ProcessEnvironmentVariables
{
  param($processVars)

  # query Machine vars from registry, ensuring expansion EXCEPT for PATH
  $vars = [Environment]::GetEnvironmentVariables('Machine').GetEnumerator() |
    % -Begin { $h = @{} } -Process { $v = if ($_.Name -eq 'Path') { $_.Value } else { [Environment]::GetEnvironmentVariable($_.Name, 'Machine') }; $h."$($_.Name)" = $v } -End { $h }

  # query User vars from registry, ensuring expansion EXCEPT for PATH
  [Environment]::GetEnvironmentVariables('User').GetEnumerator() | % {
      if ($_.Name -eq 'Path') { $vars[$_.Name] += ';' + $_.Value }
      else
      {
        $value = [Environment]::GetEnvironmentVariable($_.Name, 'User')
        $vars[$_.Name] = $value
      }
    }

  $processVars.GetEnumerator() | % { $vars[$_.Name] = $_.Value }

  Remove-Item -Path Env:\* -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Recurse

  $vars.GetEnumerator() | % { Set-Item -Path "Env:\$($_.Name)" -Value $_.Value }
}

function Reset-ProcessPowerShellVariables
{
  param($psVariables)
  $psVariables | %{
    $tempVar = $_
    if(-not(Get-Variable -Name $_.Name -ErrorAction SilentlyContinue)){
      New-Variable -Name $_.Name -Value $_.Value -Description $_.Description -Option $_.Options -Visibility $_.Visibility
    }
  }
}
'@

function Invoke-PowerShellUserCode
{
  [CmdletBinding()]
  param(
    [String]
    $Code,

    [String]
    $EventName,

    [Int]
    $TimeoutMilliseconds
  )

  if ($global:runspace -eq $null){
    # CreateDefault2 requires PS3
    if ([System.Management.Automation.Runspaces.InitialSessionState].GetMethod('CreateDefault2')){
      $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    }else{
      $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    }

    $global:puppetPSHost = New-Object Puppet.PuppetPSHost
    $global:runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($global:puppetPSHost, $sessionState)
    $global:runspace.Open()
  }

  try
  {
    $ps = $null
    $global:puppetPSHost.ResetExitStatus()

    if ($PSVersionTable.PSVersion -ge [Version]'3.0') {
      $global:runspace.ResetRunspaceState()
    }

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $global:runspace
    [Void]$ps.AddScript($global:ourFunctions)
    $ps.Invoke()


    if(!$global:environmentVariables){
      $ps.Commands.Clear()
      $global:environmentVariables = $ps.AddCommand('Get-ProcessEnvironmentVariables').Invoke()
    }

    if($PSVersionTable.PSVersion -le [Version]'2.0'){
      if(!$global:psVariables){
        $global:psVariables = $ps.AddScript('Get-Variable').Invoke()
      }

      $ps.Commands.Clear()
      [void]$ps.AddScript('Get-Variable -Scope Global | Remove-Variable -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue')
      $ps.Invoke()

      $ps.Commands.Clear()
      [void]$ps.AddCommand('Reset-ProcessPowerShellVariables').AddParameter('psVariables', $global:psVariables)
      $ps.Invoke()
    }

    $ps.Commands.Clear()
    [Void]$ps.AddCommand('Reset-ProcessEnvironmentVariables').AddParameter('processVars', $global:environmentVariables)
    $ps.Invoke()

    # we clear the commands before each new command
    # to avoid command pollution
    $ps.Commands.Clear()
    [Void]$ps.AddScript($Code)

    # out-default and MergeMyResults takes all output streams
    # and writes it to the PSHost we create
    # this needs to be the last thing executed
    [void]$ps.AddCommand("out-default");

    # if the call operator & established an exit code, exit with it
    [Void]$ps.AddScript('if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }')

    if($PSVersionTable.PSVersion -le [Version]'2.0'){
      $ps.Commands.Commands[0].MergeMyResults([System.Management.Automation.Runspaces.PipelineResultTypes]::Error, [System.Management.Automation.Runspaces.PipelineResultTypes]::Output);
    }else{
      $ps.Commands.Commands[0].MergeMyResults([System.Management.Automation.Runspaces.PipelineResultTypes]::All, [System.Management.Automation.Runspaces.PipelineResultTypes]::Output);
    }
    $asyncResult = $ps.BeginInvoke()

    if (!$asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)){
      throw "Catastrophic failure: PowerShell module timeout ($TimeoutMilliseconds ms) exceeded while executing"
    }

    $ps.EndInvoke($asyncResult)

    [Puppet.PuppetPSHostUserInterface]$ui = $global:puppetPSHost.UI
    [string]$text = $ui.Output

    @((New-XmlResult -exitcode $global:puppetPSHost.Exitcode -output $text -errormessage $null), $EventName)
  }
  catch
  {
    try
    {
      if ($global:runspace) { $global:runspace.Dispose() }
    }
    finally
    {
      $global:runspace = $null
    }
    if(($global:puppetPSHost -ne $null) -and $global:puppetPSHost.ExitCode){
      $ec = $global:puppetPSHost.ExitCode
    }else{
      # This is technically not true at this point as we do not
      # know what exitcode we should return as an unexpected exception
      # happened and the user did not set an exitcode. Our best guess
      # is to return 1 so that we ensure Puppet reports this run as an error.
      $ec = 1
    }
    $output = $_.Exception.Message | Out-String
    @((New-XmlResult -exitcode $ec -output $null -errormessage $output), $EventName)
  }
  finally
  {
    if ($ps -ne $null) { [Void]$ps.Dispose() }
  }
}

function Signal-Event
{
  [CmdletBinding()]
  param(
    [String]
    $EventName
  )

  $event = [System.Threading.EventWaitHandle]::OpenExisting($EventName)

  [System.Diagnostics.Debug]::WriteLine("Signaling event $EventName")

  [Void]$event.Set()
  [Void]$event.Close()
  if ($PSVersionTable.CLRVersion.Major -ge 3) {
    [Void]$event.Dispose()
  }

  [System.Diagnostics.Debug]::WriteLine("Signaled event $EventName")
}


function Write-StreamResponse
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [IO.StreamWriter]
    $PipeWriter,

    [Parameter(Mandatory = $true)]
    [String]
    $Response
  )

  [System.Diagnostics.Debug]::WriteLine("Writing $Response to IO.StreamWriter")

  # this is a simple string write and flush
  $PipeWriter.WriteLine($Response)
  $PipeWriter.Flush()

  [System.Diagnostics.Debug]::WriteLine("Wrote $Response to IO.StreamWriter")
}

# Message format is:
# 1 byte - command identifier
#     0 - Exit
#     1 - Execute
# [optional] 4 bytes - Big Endian encoded 32-bit code block length for execute
# [optional] variable length - code block
function Read-Stream
{
  [CmdletBinding()]
  param (

    [Parameter(Mandatory = $true)]
    [IO.StreamReader]
    $PipeReader
  )

  # command identifier is a single value
  $command = $PipeReader.ReadLine()

  [System.Diagnostics.Debug]::WriteLine("Command id $command read from pipe")

  switch ($command)
  {
    # Exit
    '0' { return @{ Command = 'Exit' }}

    # Execute
    '1' { $parsed = @{ Command = 'Execute' } }

    default { throw "Unexpected command identifier: $command" }
  }

  # process the pipe more, given that this is an Execute
  $parsed.Length = [Convert]::ToInt32($PipeReader.ReadLine())

  # $length = New-Object Byte[] 4
  # $PipeReader.ReadBlock(0, 4, $length) | Out-Null

  # # determine the length of user data and allocate a place to hold it
  # $parsed.Length = [BitConverter]::ToInt32($length, 0)
  $parsed.RawData = New-Object Char[] $parsed.Length

  [System.Diagnostics.Debug]::WriteLine("Expecting $($parsed.Length) UTF-8 characters")

  # keep draining pipe in 4096 byte chunks until expected number of chars read
  $chunkLength = 4096
  $read = 0
  $buffer = New-Object Char[] $chunkLength
  while ($read -lt $parsed.Length)
  {
    # ensure that only expected chars are waited on
    $toRead = [Math]::Min(($parsed.Length - $read), $chunkLength)

    [System.Diagnostics.Debug]::WriteLine("Attempting to read $toRead UTF-8 characters")

    # this should return either a full buffer or remaining chars
    $lastRead += $PipeReader.ReadBlock($buffer, 0, $toRead)

    [System.Diagnostics.Debug]::WriteLine("Buffer received $lastRead UTF-8 characters")

    # copy the $lastRead number of chars read into $buffer out to RawData
    [Array]::Copy($buffer, 0, $parsed.RawData, $read, $lastRead)

    # and keep track of total chars read
    $read += $lastRead
  }

  [System.Diagnostics.Debug]::WriteLine("Buffer received total $read UTF-8 characters")

  # ensure data is a UTF-8 string
  $parsed.Code = [System.Text.Encoding]::UTF8.GetString($parsed.RawData)

  [System.Diagnostics.Debug]::WriteLine("User code:`n`n$($parsed.Code)")

  return $parsed
}

function Start-PipeServer
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [String]
    $ListenerReadyEventName,

    [Parameter(Mandatory = $true)]
    [String]
    $CommandChannelPipeName
  )

  # this does not require versioning in the payload as client / server are tightly coupled
  $server = New-Object System.IO.Pipes.NamedPipeServerStream($CommandChannelPipeName, [IO.Pipes.PipeDirection]::InOut)

  try
  {
    # let Ruby know the server is available and listening, and the file path can be opened
    Signal-Event -EventName $ListenerReadyEventName

    # block until Ruby process connects
    $server.WaitForConnection()

    [System.Diagnostics.Debug]::WriteLine("Incoming Connection to $CommandChannelPipeName Received")

    $pipeReader = New-Object System.IO.StreamReader($server, [System.Text.Encoding]::UTF8)
    $pipeWriter = New-Object System.IO.StreamWriter($server, [System.Text.Encoding]::UTF8)

    [System.Diagnostics.Debug]::WriteLine("Opened Reader / Writer stream against pipe from PS")
    # $pipeWriter.AutoFlush = $true

    # Infinite Loop to process commands until EXIT received
    $running = $true
    while ($running)
    {
      $response = Read-Stream -PipeReader $pipeReader

      [System.Diagnostics.Debug]::WriteLine("Received $($response.Command) command from client")

      switch ($response.Command)
      {
        'Execute' {
          [System.Diagnostics.Debug]::WriteLine("Invoking user code:`n`n $($response.Code)")

          # assuming that the Ruby code always calls Invoked-PowerShellUserCode,
          # result should already be returned as XML, eventName to signal
          $result, $eventName = Invoke-Expression $response.Code

          [System.Diagnostics.Debug]::WriteLine("Will signal $eventName after writing to stream execution result:`n$result")

          Write-StreamResponse -PipeWriter $pipeWriter -Response $result

          Signal-Event -EventName $eventName
        }
        'Exit' { $running = $false }
      }
    }
  }
  catch [Exception]
  {
    [System.Diagnostics.Debug]::WriteLine("It died!`n`n$_")
  }
  finally
  {
    if ($pipeReader -ne $null) { $pipeReader.Dispose() }
    if ($pipeWriterer -ne $null) { $pipeWriter.Dispose() }
    if ($server -ne $null) { $server.Dispose() }
  }
}

Start-PipeServer -ListenerReadyEventName $InitReadyEventName -CommandChannelPipeName $NamedPipeName
