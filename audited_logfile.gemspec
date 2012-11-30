Gem::Specification.new do |s|
  s.name        = 'audited_logfile'
  s.version     = '0.0.2'
  s.date        = '2012-12-30'
  s.summary     = "audited_logfile"
  s.description = "Audited extention to log audit"
  s.authors     = ["Alexander Kiseliov"]
  s.email       = 'aakiselev@at-consulting.ru'
  s.files       = ["lib/audited_logfile.rb"]
  s.homepage    = 'https://github.com/at-consulting/audited_logfile'

  s.add_runtime_dependency "audited-activerecord", "~> 3.0"
end
