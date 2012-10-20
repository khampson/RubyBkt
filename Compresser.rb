### Compresser
#
#	Ruby interface with 7-Zip's command line component 7z.exe.
#
#	Most recently tested against 7-Zip 9.20 64-bit, although it should work in subsequent versions as long as they don't change 7-Zip's CLI.
#
#		Written by Ken Hampson, hampsonk+github@gmail.com
#
#
# 7-Zip cmdline example (no compression):
# "C:\Program Files\7-Zip\7z.exe" a -tzip -mx0 -p<pwd> <archive name> <files>
#
# Note: With the wrong password, it will appear to extract file, but the file will be invalid and the CRC check will fail.
#
# With errors:
# Extracting  foo.txt     CRC Failed
#
# Sub items Errors: 1
#
# OK:
# Everything is Ok

require 'Utils'

class Compresser
    attr_reader :files, :mode, :type, :compression, :pwd, :archName, :workdir
    attr_writer :files, :pwd, :archName, :workdir

    def initialize(archName, files, workdir, log = nil, debug = 0, logDebug = 0)
        # class constants
        @DEBUG = 1

		# Note: It is vital that this be a nested interpolation -- that is, single quotes surrounding the double quotes.
		#		This is because this ensures the entire double-quoted string is captured and escaped, including the quotes.
		#		This becomes very important when we go to execute the command later.
		#
		#		Here is the resulting string literal in irb:
		#
		#		irb(main):001:0> ZIP_PROG = '"C:\Program Files\7-Zip\7z.exe"'
		#		=> "\"C:\\Program Files\\7-Zip\\7z.exe\""
		#
        @ZIP_PROG = '"C:\Program Files\7-Zip\7z.exe"'

        # variables
        @files = files              # List of files to be zipped
        @mode = 'a'                 # Zip Mode (add, delete, extract, etc.). Defaults to add.
        @type = 'zip'               # Type of archive (zip, gzip, etc.). Defaults to zip.
        @compression = '0'          # Amount of compression (0 to copy). Defaults to copy.
        @pwd  = ''                  # Password to assign to archive
        @archName = archName        # Name of archive to create
        @workdir = workdir          # Root working path
        @log = log                  # handle to log file

        @DEBUG = debug              # debug level (for stdout)
        @LOG_DEBUG = logDebug       # debug level (for log file)
    end

    # 7-Zip refers to the mode as the "commands"
    def mode=(md)
        validModes = ['a', 'd', 'e', 'l', 't', 'u', 'x']
        
        # bail if the passed-in mode isn't one we know about
        raise InvalidModeCompException unless validModes.include?(md)
        
        @mode = md
    end

    def type=(tp)
        validTypes = ['7z', 'zip', 'gzip', 'bzip2', 'tar']
        
        # bail if the passed-in mode isn't one we currently support
        raise InvalidTypeCompException unless validTypes.include?(tp)
        
        @type = tp
    end

    # While in 7-Zip the options for this depend on the type of compression, currently
    # this is implemented for zip only.
    def compression=(cmp)
        # Currently only support zip
        raise UnsupportedCompCompException unless @type.eql?('zip')
        
        validComps = ['0', '1', '3', '5', '7', '9']

        # bail if the passed-in compression mode isn't a supported one
        raise InvalidCompCompException unless validComps.include?(cmp)
        
        @compression = cmp
    end

# Try a cmdline of this form (with the I/O redirects) and then read the results from the file:
# 	"C:\Program Files\7-Zip\7z.exe" a -tzip -mx0 -pfoo c:\tmp\test.zip c:\tmp\test.file1 c:\tmp\test.file2 > comp.out 2>&1
    def compress
        # make sure we have something to compress and a name for the archive
        raise NoFilesCompException      if @files.size == 0
        raise NoArchNameCompException   if @archName.empty?

        cmd = "#{@ZIP_PROG} #{@mode} -t#{@type} -mx#{@compression}"
        
        # add the password if one is set
        cmd += " -p#{@pwd}" if @pwd
        
        # complete the cmdline with the archive name...
        cmd += " \"#{@archName}\""
        
        # ...and the file list        
        filestr = ''
        @files.each do |f|
            Utils.printMux(@log, "f: #{f}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
            filestr += "\"#{f}\" "
            Utils.printMux(@log, "filestr: #{filestr}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_MED)
        end
		
		# cleanup any leading or trailing whitespace
        filestr.strip!

        Utils.printMux(@log, "filestr: #{filestr}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

        filestr.tr!('/', '\\')          # make sure we have w32-style slashes

        cmd += " #{filestr}"

        # Tack on the file redirect components. Redirect all stdout and stderr output to a file.
        outfile = "#{@workdir}\\comp.out"
        cmd += " > \"#{outfile}\" 2>&1"
        
        Utils.printMux(@log, "Compression command: #{cmd}")
 
        # Now create the cmd file
        begin
            cmdfile = createCmdfile('comp', cmd)
			raise CmdfileCreationException unless cmdfile
            Utils.printMux(@log, "cmdfile: #{cmdfile}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

            # Do the actual compression
            success = system(cmdfile)

            # Read the output out of the output file so we can determine if the compression run went OK
            f = File.new(outfile, "r")
            cmdout = f.readlines.join()
            f.close()

            Utils.printMux(@log, "Command Output:\n#{cmdout}")

            unless success
                Utils.printMux(@log, "Error running '#{cmdfile}': #{$?}")
                raise NoSuccessCompException
            end

            # grep for errors
            cmdout =~ /Sub items Errors: (\d+)/i
            errors = $1.to_i
            Utils.printMux(@log, "errors: #{errors}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
            
            # grep for CRC check failures
            crcfail = cmdout =~ /CRC Failed/i
            Utils.printMux(@log, "crcfail: #{crcfail}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    
            # grep for system errors
            syserr = cmdout =~ /System error:/i
            Utils.printMux(@log, "syserr: #{syserr}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    
            raise CompFailedCompException if (errors > 0 or crcfail or syserr)

            # grep for a duplicate-files error
            err = cmdout =~ /Error:\s+Duplicate filename:\s+(.+)/im

            if err
                Utils.printMux(@log, "Duplicate files:\n#{$1}")
                raise DuplicateFileCompException
            end

            # grep for explicit success. If we didn't get any errors, but also didn't get
            # the 'ok', then assume something went wrong. 
            success = cmdout =~ /Everything is Ok/i
            raise NoSuccessCompException unless success 
        ensure
            Utils.printMux(@log, "Cleaning up files")
            File.delete(cmdfile)    if cmdfile and File.exists?(cmdfile)
            File.delete(outfile)    if outfile and File.exists?(outfile)
        end

		# return the output from the command so the caller can do something with it if desired
        return cmdout
    end

	# Create a .cmd file with the specified label and command string.
    def createCmdfile(label, cmd)
        filename = "#{@workdir}\\#{label}.cmd"
        Utils.printMux(@log, "filename: #{filename}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

		# Check to see if the directory in which we are to create the cmd file actually exists. If not, create it.
		unless File.exists?(@workdir)
			begin
				Utils.printMux(@log, "Creating cmd-file directory '#{@workdir}'...")
				Dir.mkdir(@workdir)
			rescue SystemCallError => sce
				Utils.printMux(@log, "Could not create cmd-file directory '#{@workdir}'. Error: " + sce.to_s())
			end
		end
		
        begin
            Utils.printMux(@log, "Calling File.new", @DEBUG, @LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
            f = File.new(filename, "w+")
            Utils.printMux(@log, "Done calling File.new", @DEBUG, @LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
        rescue Exception => e
            Utils.printMux(@log, "Could not create command file '#{filename}'. Got exception: #{e}")
            puts
			return nil
        end

        f.puts "\@echo on"
        f.puts cmd        
        f.close()
        
        return filename
    end
end

#
## Exceptions that can be raised by this class
#

# Raised when an invalid mode is supplied
class InvalidModeCompException < StandardError
end

# Raised when am invalid type of compression was specified 
class InvalidTypeCompException < StandardError
end

# Raised when an unsupported type of compression was specified
class UnsupportedCompCompException < StandardError 
end

# Raised when an invalid mode was specified
class InvalidCompCompException < StandardError
end

# Raised when no files to compress were supplied
class NoFilesCompException < StandardError
end

# Raised when no archive name was supplied
class NoArchNameCompException < StandardError 
end

# Raised when compression explicitly fails with errors 
class CompFailedCompException < StandardError
end

# Raised when compression fails implicitly (no 'ok' message)
class NoSuccessCompException < StandardError
end

# Raised when compression fails due to a duplicate file name
class DuplicateFileCompException < StandardError
end

# Raised when the cmdfile could not be created
class CmdfileCreationException < StandardError
end
