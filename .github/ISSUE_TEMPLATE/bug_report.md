---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

Before reporting a problem, please check the [troubleshooting document on the wiki](https://github.com/marcone/teslausb/wiki/Troubleshooting) and the [FAQ](https://github.com/marcone/teslausb/wiki/FAQ) to see if they can help resolve the problem you're having. Note especially the first item on the troubleshooting page, since using a charge-only cable instead of a true USB cable is the most common source of problems. 

You can also ask for help on [Discord](https://discord.gg/b4MHf2x)

When reporting a new issue, please include diagnostics if possible. Ssh in to the Pi, run these commands: 
```
sudo -i
/root/bin/setup-teslausb selfupdate
/root/bin/setup-teslausb diagnose > /tmp/diagnostics.txt
```
and then attach the /tmp/diagnostics.txt file to the issue you're creating.
