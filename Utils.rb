### Utility
#
#	Class containing miscellaneous constants and utility functions used in the accompanying code.
#
#	Note: Most, if not all, of the methods within this function will be class methods as opposed to instance methods,
#		  as this class is meant to serve as more of a collector of the methods as opposed to an instantiatable object.
#
#		Written by Ken Hampson, hampsonk+github@gmail.com
#
require 'Time'

class Utils
	# Constants
    DEBUG_ALWAYS = 0
	DEBUG_OFF	 = 0		# When using this as the debug setting instead of threshold, it should be 0 for off for the 'if debug' comparison below
    DEBUG_LOW    = 1
    DEBUG_MED    = 2
    DEBUG_HIGH   = 3
    DEBUG_NEVER  = 256
    
    LOG_ALWAYS   = 0
	LOG_OFF	 	 = 0		# When using this as the log setting instead of threshold, it should be 0 for off for the 'if log' comparison below
    LOG_LOW      = 1
    LOG_MED      = 2
    LOG_HIGH     = 3
    LOG_NEVER    = 256

	# Class variables
    @@DEBUG = 0

	# General purpose logging function which multiplexes between stdout and the specified log file.
	# The output can be dampened by optional threshold arguments for both stdout and the log file.
    def Utils.printMux(log, msg, debug = 0, logDebug = 0, debugThreshold = 0, logDebugThreshold = 0)
        puts "debug: #{debug}, logDebug: #{logDebug}" if @@DEBUG >= 1
        puts "debugThreshold: #{debugThreshold}, logDebugThreshold #{logDebugThreshold}" if @@DEBUG >= 1
        
        time = getTimeStr()
        puts "#{time}  #{msg}"     if debug >= debugThreshold
        log.puts "#{time}  #{msg}" if log and (logDebug >= logDebugThreshold)
    end

	# Get the current time and return it as a formatted string
    def Utils.getTimeStr
        t = Time.new
        return t.strftime("%m/%d/%Y %H:%M:%S")        
    end
	
	# Given the root path, number of files, minimum single size, maximum single file size, stringInterval (how large each string written to the file is)
	# and max total size, generate a set of files at random to use for testing purposes, in particular with Bucket (bkt.rb).
	def Utils.createTestFileSet(rootPath, numFiles, minSingleSize, maxSingleSize, totalSize, stringInterval, log)
		randGen = Random.new()	# use arbitrary seed
		runningTotal = 0
		sizeLeft = totalSize

		1.upto(numFiles) do |num|
			Utils.printMux(log, "** minSingleSize: #{minSingleSize}, maxSingleSize: #{maxSingleSize}, sizeLeft: #{sizeLeft}", DEBUG_NEVER, LOG_ALWAYS, DEBUG_NEVER, LOG_ALWAYS)

			# Make sure the min and max ranges aren't more than the size we have remaining
			maxEnd = [maxSingleSize, sizeLeft].min
			minEnd = [minSingleSize, sizeLeft].min

			Utils.printMux(log, "\t** minEnd: #{minEnd}, maxEnd: #{maxEnd}", DEBUG_NEVER, LOG_ALWAYS, DEBUG_NEVER, LOG_ALWAYS)

			# Generate a random number between the range of the minimum single size and whichever is less: the max single size or the size left (exclusive).
			# If the min and max are equal, then that means we happened to hit the target space right on the head, so just use that value.
			unless (minEnd == maxEnd)
				size = randGen.rand(minEnd...maxEnd)
			else
				Utils.printMux(log, "\t** minEnd and maxEnd equal -- setting to #{minEnd}", DEBUG_NEVER, LOG_ALWAYS, DEBUG_NEVER, LOG_ALWAYS)
				size = minEnd
			end

			runningTotal += size
			sizeLeft -= size

			Utils.printMux(log, "\nGenerated size #{num}: #{size}")
			Utils.printMux(log, "\tSize left: #{sizeLeft}")
			
			# create a file of the specified size in the root path, creating the directory if it doesn't exist first
			unless File.exists?(rootPath)
				begin
					Utils.printMux(log, "Creating directory '#{rootPath}'...")
					Dir.mkdir(rootPath)
				rescue SystemCallError => sce
					Utils.printMux(log, "Could not create directory '#{rootPath}'. Error: " + sce.to_s())
				end
			end
			
			path = rootPath + "\\testFile" + num.to_s() + ".dat"

			# If sizeLeft is 0, no need to proceed, so delete the last file if it still exists (size we always clobber, it must be from a prior run)
			# and then bail out of the upto loop.
			if (sizeLeft == 0 and File.exists?(path))
				Utils.printMux(log, "sizeLeft is 0 and file '#{path}' exists - deleting...")
				File.delete(path)
				break
			end
			
			# Open the file read/write with clobber if it exists and creation if it doesn't
			f = File.open(path, File::RDWR | File::TRUNC | File::CREAT)

			# Now, generate a large string to be used to write iteratively to the file until its target size is reached.
			# To strike a balance between efficiency and memory usage, the string here should be large, but not colossal.
			# Initial testing was done with a target string interval of 64K.
			largeString = "1" * (stringInterval - 1) + "\n"				# subtract 1 from the interval for the newline
			fileSizeLeft = size
			
			Utils.printMux(log, "Writing out contents for file '#{path}' of size #{size} bytes")

			writeIter = 0
			while (fileSizeLeft > stringInterval)
				writeIter++
				f.write(largeString)
				fileSizeLeft -= stringInterval
				
				# Dampen this extensively so it's not quite so noisy but still provides a good gauge on progress
				Utils.printMux(log, "\tsizeLeft: #{fileSizeLeft}") if (writeIter % 25)
			end
			
			# now write out a string of the remaining size
			largeString = "1" * (fileSizeLeft - 1) + "\n"					# subtract 1 from the interval for the newline
			Utils.printMux(log, "\tWriting out remaining bytes: #{fileSizeLeft}")
			f.write(largeString)
			
			f.close()
		end
		
		Utils.printMux(log, "Total size: #{runningTotal}")
	end
end
