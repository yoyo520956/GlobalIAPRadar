import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_175 as P
apps = {}
for arg in sys.argv[1:]:
    name, _, appid = arg.partition("=")
    apps[name] = int(appid)
P.APPS = apps
P.main()
