### FileSet
#
#	Class to hold information about a set of files, such as their size and the total max allowable size of the set.
#	Tracks the running total size and if the set has room to add another file to the set.

#	An exception is raised if there is insufficient room to add another item.
#
#		Written by Ken Hampson, hampsonk+github@gmail.com

require 'Utils'

class FileSet
    attr_reader :files, :fileSep, :maxSize, :size
    attr_writer :files, :fileSep, :maxSize, :size

    def initialize(maxSize, log = nil, debug = 0, logDebug = 0)
        # class constants
        @DEBUG = debug
        @LOG_DEBUG = logDebug

        # variables
        @log = log
        @files = {}
        @fileSep = '\\'
        @maxSize = maxSize
        @size = 0
    end

	# Add a file to the set, if there is room
    def add(file, fsize)
        raise FilesTooBigException.new(@size + fsize, @maxSize) if (@size + fsize) > @maxSize 

        @files[file] = fsize
        @size += fsize
    end

	# Return the list of file names. Since this is abstracted, it can't just be used with attr_reader.
    def fileNames
        return @files.keys
    end
 
	# Stringify the object in a human-readable form
    def to_s
        num = @files.size()
        sizeKB = @size / 1024			# Integer division here to truncate the fractional KB
        sizeMB = sizeKB / 1024.0
        sizeGB = sizeMB / 1024.0

        # Use a format string so we can restrict the precision on the floating-point values
        str = sprintf("Files (%d, %d bytes / %d KB / %.2f MB / %.2f GB):\n", num, size, sizeKB, sizeMB, sizeGB)

        files.each_pair do |key, val|
            str += "\t#{key} (#{val})\n"
        end
        
        return str
    end
    
	# Return the number of files. Since this is abstracted, it can't just be used with attr_reader.
    def numfiles()
        return @files.size()
    end

    # Since this is a hash-based data structure, this isn't a 'pop' method in the strictest sense.
    # Rather, we'll take the list of keys, and pop the last one of those, returning the resulting
    # key/value pair.
    def pop()
        lastkey = @files.keys.pop()
        lastval = @files.delete(lastkey)
 
        # subtract the size of the file we're removing from the running total
        @size -= lastval
        return lastkey, lastval
    end
end

#
## Exceptions this class can return are below.
#

class FilesTooBigException < StandardError
    attr :size, :maxSize

    def initialize(size, maxSize)
        @size = size
        @maxSize = maxSize
    end
    
    def to_s()
        return "Current size of #{@size} is bigger than the max size of #{@maxSize}" 
    end
end
