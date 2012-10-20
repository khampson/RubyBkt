# Load the files in gvim in remote tabs, assuming a server name of GVIM (must be currently running).

gvim --servername GV_RUBY_BKT
gvim --servername GV_RUBY_BKT --remote-tab bkt.rb \
					   bucket.log \
					   FileSet.rb \
					   testDriver.rb \
					   Compresser.rb \
					   readme.txt \
					   Utils.rb \
					   FileBucketSorter.rb \
					   testDriver.log



