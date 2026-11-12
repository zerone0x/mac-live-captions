let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
try p.run()
