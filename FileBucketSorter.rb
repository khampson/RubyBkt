### FileBucketSorter
#
#	Class that implements a bucket-sorting algorithm aimed at sets of files.
#
#		Written by Ken Hampson, hampsonk+github@gmail.com


require 'FileSet'
require 'Utils'

# Override some of the built-in File class to compensate for a Ruby bug.
#
# Note, this was explicitly needed in earlier versions of Ruby -- they did not support getting the size of files > 2 GB in size.
# In Ruby 1.9.3, this bug is no longer present -- File.size can return the size of files > 2 GB. However, I am leaving this code
# present and active for two main reasons:
#	1) It provides some insight into my thought process for working around issues discovered in code over which I have no direct control and
#	2) Leaving this code active ensures that we can have one common codepath for getting the file size and that it will work in both older
#	   and newer versions of Ruby, without the overhead of having to do runtime Ruby version checking and switching between two different methods.
class File
    @DEBUG = 0

    # The File class's size method returns a Fixnum, and so therefore is
    # limited to 2^31 bytes (no longer the case in 1.9.3, but see above why this code remains active).
	# Work around the size limitation by shelling out to get the size.
    def File.size_big(file_name)
        fileNameW32 = file_name.tr('/', '\\')
        cmd = "dir \"#{fileNameW32}\""
        puts "cmd: '#{cmd}'" if @DEBUG >= 1

        cmdout = `#{cmd}`

        puts "cmdout:\n#{cmdout}" if @DEBUG >= 1
        
        #                             Dir    month    day     year        hour    min
        regex = %r{Directory \s of \s .+? \s+ \d+ / \d+ / \d+ \s+ \d+ : \d+ \s+
                   ([\d,]+) \s+ .+? $}imx
                   
        puts "Regex: #{regex}" if @DEBUG >= 1

        cmdout =~ regex
        size = $1
        
        puts "#{file_name}: #{size} bytes"  if @DEBUG >= 1
        
        # Now remove the commas and convert from a string to an integer
        size.tr!(',', '')
        return size.to_i()
    end
end


class FileBucketSorter
    attr_reader :fileSets, :totalSize, :sleepInterval
    attr_writer :sleepInterval

    def initialize(log = nil, debug = 0, logDebug = 0)
        # class constants
        @DEBUG = debug
        @LOG_DEBUG = logDebug

        # variables
        @log = log
        @bucketInt = 100 * 1024 * 1024  # default to 100 MB buckets
        @data = {}
        @sortedBuckets = []
        @fileSets = []
        @sleepInterval = 0.1			# in seconds
    end
    
    def add(file)
        size = File.size(file)
		
		# Calculate the "bucketed size" for this file.

		# Essentially, this calculation determines bucket placement for the file by rounding down the file size to the nearest
		# bucket based on the specified bucket granularity.
		#
		# Thus, if size were, say, ~1439 MB, the parenthetical of this expression would be ~39 MB, and the expression would round
		# the file size down to the 1400 bucket.
        bucketedSize = size - (size % @bucketInt)

        # Cover the case with small files where the bucketed size can go negative
        bucketedSize = 0    if bucketedSize < 0

        Utils.printMux(@log, "bucketedSize = #{bucketedSize}", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
        
        @data[bucketedSize] ||= []          # make sure we've initialized this slot (else return itself)
        @data[bucketedSize] << file

        Utils.printMux(@log, "data\n" + @data.pretty_inspect(), @DEBUG, @LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_MED)
    end

    def dump
        str = "DEBUG = #{@DEBUG}\n"
        str +=  "bucketInt = #{@bucketInt}\n"
        str += @data.pretty_inspect()
        
        return str
    end
    
    # Get the list of buckets, sorted from largest to smallest
    def buckets()
        @sortedBuckets = @data.keys.sort {|x,y| y <=> x}
        Utils.printMux(@log, "buckets> sortedBuckets:" + @sortedBuckets.pretty_inspect(), @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    end

	# Iterate over the buckets to fit a subset of the files into a set of the target size
    def fitFiles(target)
       buckets()
       runningSize = 0
       fileSet = FileSet.new(target, @log, @DEBUG, @LOG_DEBUG)
       
       # Go thru each bucket...
       @sortedBuckets.each do |bkt|
           Utils.printMux(@log, "Processing bucket '#{bkt}'")

           # ... And each file in the bucket
           @data[bkt].each do |file|               
               Utils.printMux(@log, "\tProcessing file '#{file}'")

               # The regular call to size won't work with larger (> 2 GB) files in some versions of Ruby, so call the custom version added above.
               fsize = File.size_big(file)

               Utils.printMux(@log, "\t\t      fsize: #{fsize}\n", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
               Utils.printMux(@log, "\t\trunningSize: #{runningSize}\n", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
               Utils.printMux(@log, "\t\t     target: #{target}\n", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

			   # Sanity check the file size
               if (fsize < 0)
                    Utils.printMux(@log, "\t\t*** WARNING: fsize < 0 - skipping!\n", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
                    next
               end

               # Make sure this file won't push us over the limit
               if (fsize + runningSize) < target
                   # take the first file in this bucket 
                   Utils.printMux(@log, "\t\tAdding '#{file}' and removing from bucket")
                   fileSet.add(file, fsize)
                   runningSize += fsize
                   
                   # Remove the file from the original list
                   @data[bkt].delete(file)
                   
                   # See if we should remove the bucket, too
                   if @data[bkt].size() == 0
                       @data.delete(bkt)
                       Utils.printMux(@log, "Removed bucket '#{bkt}'\n")
                   end
               else
                   # Go to the next bucket and look at smaller files
                   Utils.printMux(@log, "\t\tDropping down to next bucket\n")
                   break
               end

               # Give the CPU a bit of a break in between files
               sleep @sleepInterval
           end  # iterate files

           # Give the CPU a bit of a break in between buckets
           sleep @sleepInterval
        end  # iterate buckets
       
       # Save off the running size in the object
       @totalSize = runningSize
       
       # Save off the file set
       @fileSets << fileSet

       Utils.printMux(@log, "totalSize: #{totalSize}\n", @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
       Utils.printMux(@log, "fileSets:\n" + @fileSets.pretty_inspect(), @DEBUG, @LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

       return fileSet
    end # fitFiles
    
    def empty?
        return (@data.size() == 0)
    end
end
