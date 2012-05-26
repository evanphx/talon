require 'rake/testtask'

task :default => :integration

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/test*.rb'] + FileList['test/**/test*.rb']
  t.verbose = true
end

task :integration do
  ruby "test/integration/run.rb"
end
