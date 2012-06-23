
Dir.chdir File.dirname(__FILE__)

if dir = ARGV.shift
  files = Dir["#{dir}/*.tln"]
else
  files = Dir["*.tln"] + Dir["typecheck/*.tln"]
end

fails = false

files.each do |f|
  lines = File.readlines(f)
  checks = lines.grep(/-- check: (.*)/) { $1 }

  if lines.first =~ /-- error: (.*)/
    e = $1
    out = `ruby -I../../lib ../../bin/talon #{f}`
    if $?.exitstatus == 0
      puts "FAIL (compile, should fail) #{f}"
      fails = true
    elsif !out.split("\n").grep(Regexp.new(Regexp.quote(e))).empty?
      puts "PASS #{f}"
    else
      puts "FAIL #{f}"
      puts " Expected: '#{e}' in <<-OUTPUT"
      puts out
      puts " OUTPUT"
      fails = true
    end

    next
  end

  system "ruby -I../../lib ../../bin/talon #{f}"
  if $?.exitstatus != 0
    puts "FAIL (compile) #{f}"
    fails = true
    next
  end

  exe = File.basename f, ".tln"

  out = `./#{exe}`

  if !out
    puts "FAIL (run) #{f}"
    File.unlink exe if File.exists? exe
    fails = true
    next
  end

  output = out.split("\n")

  if checks != output
    puts "FAIL (check) #{f}"
    fails = true
    puts "#{output.inspect} not equal to #{checks.inspect}"
  else
    puts "PASS #{f}"
  end

  File.unlink exe

end

exit 1 if fails
