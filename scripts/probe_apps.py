import sys
sys.path.insert(0, "/var/minis/workspace/GlobalIAPRadar/scripts")
import probe_175 as P
apps = {}
for arg in sys.argv[1:]:
    name, _, appid = arg.partition("=")
    apps[name] = int(appid)
P.APPS = apps
P.main()
