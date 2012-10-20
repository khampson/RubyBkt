### testDriver.rb
#
#	Test driver. This drives the creation of a randomized file data set for Bucket to use.
#
#		Written by Ken Hampson, hampsonk+github@gmail.com
#

# Built-in modules
require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'pp'

# Custom modules
require 'Utils'

LOGFILE_NAME = "testDriver.log"
PROG_NAME = "Test Driver"
PROG_VER = "1.0"

# Set the thresholds for console and logfile logging
DEBUG       = Utils::DEBUG_OFF
LOG_DEBUG   = Utils::LOG_LOW

# Test specifics
NUM_FILES = 20									# Default number of files if not user-specified
MIN_FILE_SIZE_BYTES = 30 * 1024 * 1024			# 30 MB		- This is the min size of an individual file (the min of this size or the total remaining size will be used)
MAX_FILE_SIZE_BYTES = 1500 * 1024 * 1024		# 1500 MB	- This is the max size of an individual file (the min of this size or the total remaining size will be used)
TOTAL_SIZE_BYTES	= 15 * 1024 * 1024 * 1024	# 15 GB 	- This is the max total size of the files
STRING_INTERVAL		= 1024 * 1024				# 1 MB 		- This is the size of each string written out to the test files.

# Setup the log file (when log gets garbage-collected, log will be closed)
log = File.open(LOGFILE_NAME, File::WRONLY | File::APPEND | File::CREAT)
log.puts "######################################################################################"
log.puts "#{PROG_NAME} #{PROG_VER}" 


class Optparse
    # Return a structure describing the options, created with the hash-esque OpenStruct class.
    def self.parse(args)
        # Defaults here
  		options = OpenStruct.new	# cmdline options container
    		
        opts = OptionParser.new do |opts|
            opts.banner = "Usage: testDriver.rb [options]"
    			
            opts.separator ""
            opts.separator "Specific options:"
    			
            # Mandatory arguments
            opts.on("-path", "--path PATH",
                    "Root path for test operations") do |path|
                options.path = path
            end

            opts.separator ""
            opts.separator "Common options:"

			# Display the options
            opts.on_tail("-h", "--help", "Show this message") do
                puts opts
                exit(0)
            end

       		opts.on_tail("-v", "Show version") do
                puts "#{PROG_NAME} #{PROG_VER}"
                exit(0)
            end

            opts.on("--num N", Integer, "Generate N test files") do |n|
                options.numFiles = n
            end
        end
    	
        opts.parse!(args)

        return options
    end  # parse()
end  # class Optparse

Utils.printMux(log, "Creating Optparse object", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
options = Optparse.parse(ARGV)
Utils.printMux(log, "Done creating Optparse object", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)

# Exit if no path was supplied
if not options.path
	Utils.printMux(log, "No path was supplied. Exiting.", DEBUG, LOG_DEBUG, Utils::DEBUG_ALWAYS, Utils::LOG_ALWAYS)
	exit(1)
end

# Determine the source of the number-of-files setting
numFiles = 0
if options.numFiles
	Utils.printMux(log, "Number of files user specified at #{options.numFiles}")
	numFiles = options.numFiles
else
	Utils.printMux(log, "Using default number of files (#{NUM_FILES})")
	numFiles = NUM_FILES
end

# Now generate the test file data set
Utils.createTestFileSet(options.path, numFiles, MIN_FILE_SIZE_BYTES, MAX_FILE_SIZE_BYTES, TOTAL_SIZE_BYTES, STRING_INTERVAL, log)

