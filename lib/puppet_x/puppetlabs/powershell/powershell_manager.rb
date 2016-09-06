require 'rexml/document'
require 'securerandom'
require 'open3'
require 'base64'
require 'ffi' if Puppet::Util::Platform.windows?

module PuppetX
  module PowerShell
    class PowerShellManager
      extend FFI::Library if Puppet::Util::Platform.windows?

      @@instances = {}

      def self.instance(cmd, init_ready_event_name, named_pipe_name)
        @@instances[cmd] ||= PowerShellManager.new(cmd, init_ready_event_name, named_pipe_name)
      end

      def self.win32console_enabled?
        @win32console_enabled ||= defined?(Win32) &&
          defined?(Win32::Console) &&
          Win32::Console.class == Class
      end

      def self.supported?
        Puppet::Util::Platform.windows? && !win32console_enabled?
      end

      def initialize(cmd, init_ready_event_name, named_pipe_name)
        # create the event for PS to signal once the pipe server is ready
        init_ready_event = self.class.create_event(init_ready_event_name)

        # @stdin, @stdout, @stderr, @ps_process = Open3.popen3(cmd)
        @stdout, threads = Open3.pipeline_r(cmd)
        @ps_process = threads[0]

        Puppet.debug "#{Time.now} #{cmd} is running as pid: #{@ps_process[:pid]}"

        # wait for the pipe server to signal ready, and fail if no response in 10 seconds
        ps_pipe_wait_ms = 10 * 1000
        if WAIT_TIMEOUT == self.class.wait_on(init_ready_event, ps_pipe_wait_ms)
          msg = 'Failure waiting for PowerShell process #{@ps_process[:pid]} to start pipe server'
          raise Puppet::Util::Windows::Error.new(msg)
        end

        @pipe = File.open("\\\\.\\pipe\\#{named_pipe_name}" , 'r+')

        Puppet.debug "#{Time.now} PowerShell initialization complete for pid: #{@ps_process[:pid]}"

        at_exit { exit }
      end

      def execute(powershell_code, timeout_ms = 300 * 1000)
        output_ready_event_name =  "Global\\#{SecureRandom.uuid}"
        output_ready_event = self.class.create_event(output_ready_event_name)

        code = make_ps_code(powershell_code, output_ready_event_name, timeout_ms)
        out = exec_read_result(code, output_ready_event)

        # Powershell adds in newline characters as it tries to wrap output around the display (by default 80 chars).
        # This behavior is expected and cannot be changed, however it corrupts the XML e.g. newlines in the middle of
        # element names; So instead, part of the XML is Base64 encoded prior to being put on STDOUT and in ruby all
        # newline characters are stripped. Then where required decoded from Base64 back into text
        out = REXML::Document.new(out.gsub(/\n/,""))

        # picks up exitcode, errormessage and stdout
        props = REXML::XPath.each(out, '//Property').map do |prop|
          name = prop.attributes['Name']
          value = (name == 'exitcode') ?
            prop.text.to_i :
            (prop.text.nil? ? nil : Base64.decode64(prop.text))
          [name.to_sym, value]
        end

        Hash[ props ]
      ensure
        CloseHandle(output_ready_event) if output_ready_event
      end

      def exit
        Puppet.debug "PowerShellManager exiting..."
        write_pipe(pipe_command(:exit))
        @stdout.close

        exit_msg = "PowerShell process did not terminate in reasonable time"
        begin
          Timeout.timeout(3) do
            Puppet.debug "Awaiting PowerShell process termination..."
            @exit_status = @ps_process.value
          end
        rescue Timeout::Error
        end

        exit_msg = "PowerShell process exited: #{@exit_status}" if @exit_status
        Puppet.debug(exit_msg)
        if @ps_process.alive?
          Puppet.debug("Forcefully terminating PowerShell process.")
          Process.kill('KILL', @ps_process[:pid])
        end
      end

      def self.init_path
        # a PowerShell -File compatible path to bootstrap the instance
        path = File.expand_path('../../../templates', __FILE__)
        path = File.join(path, 'init_ps.ps1').gsub('/', '\\')
        "\"#{path}\""
      end

      def make_ps_code(powershell_code, output_ready_event_name, timeout_ms = 300 * 1000)
        <<-CODE
$params = @{
  Code = @'
#{powershell_code}
'@
  EventName = "#{output_ready_event_name}"
  TimeoutMilliseconds = #{timeout_ms}
}

Invoke-PowerShellUserCode @params

# always need a trailing newline to ensure PowerShell parses code

        CODE
      end

      private

      def self.is_readable?(stream, timeout = 0.5)
        read_ready = IO.select([stream], [], [], timeout)
        read_ready && stream == read_ready[0][0]
      end

      # copied directly from Puppet 3.7+ to support Puppet 3.5+
      def self.wide_string(str)
        # ruby (< 2.1) does not respect multibyte terminators, so it is possible
        # for a string to contain a single trailing null byte, followed by garbage
        # causing buffer overruns.
        #
        # See http://svn.ruby-lang.org/cgi-bin/viewvc.cgi?revision=41920&view=revision
        newstr = str + "\0".encode(str.encoding)
        newstr.encode!('UTF-16LE')
      end

      NULL_HANDLE = 0
      WIN32_FALSE = 0

      def self.create_event(name, manual_reset = false, initial_state = false)
        handle = NULL_HANDLE

        str = wide_string(name)
        # :uchar because 8 bits per byte
        FFI::MemoryPointer.new(:uchar, str.bytesize) do |name_ptr|
          name_ptr.put_array_of_uchar(0, str.bytes.to_a)

          handle = CreateEventW(FFI::Pointer::NULL,
            manual_reset ? 1 : WIN32_FALSE,
            initial_state ? 1 : WIN32_FALSE,
            name_ptr)

          if handle == NULL_HANDLE
            msg = "Failed to create new event #{name}"
            raise Puppet::Util::Windows::Error.new(msg)
          end
        end

        handle
      end

      WAIT_ABANDONED = 0x00000080
      WAIT_OBJECT_0 = 0x00000000
      WAIT_TIMEOUT = 0x00000102
      WAIT_FAILED = 0xFFFFFFFF

      def self.wait_on(wait_object, timeout_ms = 50)
        wait_result = WaitForSingleObject(wait_object, timeout_ms)

        case wait_result
        when WAIT_OBJECT_0
          Puppet.debug "Wait object signaled"
        when WAIT_TIMEOUT
          Puppet.debug "Waited #{timeout_ms} milliseconds..."
        # only applicable to mutexes - should never happen here
        when WAIT_ABANDONED
          msg = 'Catastrophic failure: wait object in inconsistent state'
          raise Puppet::Util::Windows::Error.new(msg)
        when WAIT_FAILED
          msg = 'Catastrophic failure: waiting on object to be signaled'
          raise Puppet::Util::Windows::Error.new(msg)
        end

        wait_result
      end

      # 1 char - command identifier
      #     0 - Exit
      #     1 - Execute
      def pipe_command(command)
        case command
        when :exit
          return "0\n"
        when :execute
          return "1\n"
        else
          # TODO: better error message
          raise Puppet::Util::Windows::Error.new('foo')
        end
      end

      def pipe_data(data)
        # raw_message = data.encode(Encoding::UTF_8).bytes.to_a
        # # iterate with each, appending to front of buffer in reverse order, which is what .NET expects
        # [raw_message.length].pack('N').bytes.each { |b| raw_message.insert(0, b) }
        # raw_message.insert(0, 1)

        # raw_message
        msg = data.encode(Encoding::UTF_8) + "\n"

        "#{msg.length}\n" + msg
      end

      def write_pipe(input)
        @pipe.write(input)
        @pipe.flush()
      rescue => e
        msg = "Error writing pipe: #{e}"
        raise Puppet::Util::Windows::Error.new(msg)
      end

      def drain_pipe(pipe, iterations = 10)
        output = []
        0.upto(iterations) do
          break if !self.class.is_readable?(pipe, 0.1)
          l = pipe.gets
          Puppet.debug "#{Time.now} PIPE> #{l}"
          output << l
        end
        output
      end

      def read_pipe(output_ready_event, wait_interval_ms = 50)
        output = []
        waited = 0

        # drain the pipe while waiting for the event signal
        while WAIT_TIMEOUT == self.class.wait_on(output_ready_event, wait_interval_ms)
          output << drain_pipe(@pipe)
          waited += wait_interval_ms
        end

        Puppet.debug "Waited #{waited} total milliseconds."

        # once signaled, ensure everything has been drained
        output << drain_pipe(@pipe, 1000)

        return output.join('')
      rescue => e
        msg = "Error reading PIPE: #{e}"
        raise Puppet::Util::Windows::Error.new(msg)
      end

      def exec_read_result(powershell_code, output_ready_event)
        write_pipe(pipe_command(:execute))
        write_pipe(pipe_data(powershell_code))
        read_pipe(output_ready_event)
      end

      if Puppet::Util::Platform.windows?
        private

        ffi_convention :stdcall

        # NOTE: Puppet 3.7+ contains FFI typedef helpers, but to support 3.5
        # use the unaliased native FFI names for parameter types

        # https://msdn.microsoft.com/en-us/library/windows/desktop/ms682396(v=vs.85).aspx
        # HANDLE WINAPI CreateEvent(
        #   _In_opt_ LPSECURITY_ATTRIBUTES lpEventAttributes,
        #   _In_     BOOL                  bManualReset,
        #   _In_     BOOL                  bInitialState,
        #   _In_opt_ LPCTSTR               lpName
        # );
        ffi_lib :kernel32
        attach_function :CreateEventW, [:pointer, :int32, :int32, :buffer_in], :uintptr_t

        # http://msdn.microsoft.com/en-us/library/windows/desktop/ms724211(v=vs.85).aspx
        # BOOL WINAPI CloseHandle(
        #   _In_  HANDLE hObject
        # );
        ffi_lib :kernel32
        attach_function :CloseHandle, [:uintptr_t], :int32

        # http://msdn.microsoft.com/en-us/library/windows/desktop/ms687032(v=vs.85).aspx
        # DWORD WINAPI WaitForSingleObject(
        #   _In_  HANDLE hHandle,
        #   _In_  DWORD dwMilliseconds
        # );
        ffi_lib :kernel32
        attach_function :WaitForSingleObject,
          [:uintptr_t, :uint32], :uint32
      end
    end
  end
end
