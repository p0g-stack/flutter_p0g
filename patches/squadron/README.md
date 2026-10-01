# Squadron series (planned)

Apps using `squadron_process` need Squadron 7.4.4 with its `0001` patch
(`Worker.channelFactory`). Today `tool/squadron.sh` in p0g-stack/squadron_process
builds the patched copy and each app adds a `dependency_overrides` entry. The
plan: the series moves here, and `precache` / `build` apply and cache it the
way they do the frb series.
