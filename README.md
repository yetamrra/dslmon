# dslmon
A low-resource monitor for network outages.

## Overview

This project was born out of my frustration with unreliable CenturyLink DSL
service in rural Colorado.  After spending months arguing with their support
agents about how often my line drops, I decided to start collecting some
objective data.  There are two basic pieces to the monitor:

1.  A script that runs on the inside of my network.  Once per minute, it pulls
    stats from my DSL modem and attempts to send them to an external site.
2.  A web server and analysis scripts running on an external server.  The web
    server records connections from the stats script, and the analysis scripts
    periodically scrape the log files to produce a snapshot of recent activity.

Any missing log entries are assumed to be an outage.  This can miss very brief
outages, and it can also record outages that aren't the fault of DSL drops
(e.g.  a power outage or upstream network problem).  Nevertheless, it has been
useful to me to give a quick overview of the stability of a connection.

If you want to use it, you _will_ have to customize it for your own hardware
and network.  Pull requests to add additional modem support or bug fixes are
welcome as long as they don't add additional requirements.

## Installation and Usage

1.  Copy `inside/uplog.sh`, `inside/config`, and the appropriate modem scripts
    (if any) to your router or an always-on computer on your local network.
1.  Edit `config` and adjust the variables for your setup.  You must at least
    set `BASE_URL` if you want to collect stats externally.
1.  It helps to touch the file referred to in `BASE_URL` on your web server.
    This prevents 404 errors from being logged.  The file itself doesn't need
    any particular contents: The local script ignores the response and the
    analysis script just needs the logs.
1.  Add a crontab on your local computer to run `uplog.sh` every minute.
1.  Copy `outside/missing_dsl_checkins.pl` to a computer that can access the
    web server logs and run it as desired to see stats.

## Example analysis

Here is an example of the output:

```
Last update: 2020-06-04 19:20
Last checkin: 2020-06-04 19:20:17
Last IP change: 2020-06-04 13:06:18 (up 6h13m)
Last speed: 14015/1092
Last uptime: 06:14

             00    02    04    06    08    10    12    14    16    18    20    22     Out ΔIP
 2020-05-21: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0
 2020-05-22: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0
 2020-05-23: __ 27                41 __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __  368   1
*2020-05-24: __ __ __ __ __ __ __ __ __ __ __ __ __ 01 __ __ __ __ __ __ __ __ __ __    1   1
 2020-05-25: __ __ __ 02 10 03 16 13 07 03 __ __ __ __ __ __ __ __ __ __ __ __ __ __   54  12
 2020-05-26: __ 02 __ 01 02 __ __ __ __ 05 01 __ __ __ __ __ __ __ __ __ __ __ __ __   11   4
 2020-05-27: __ __ __ 03 __ __ __ __ __ __ __ __ __ __ __ __ __ __ 04 __ __ __ __ __    7   2
 2020-05-28: __ __ __ 01 __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    1   1
 2020-05-29: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0
 2020-05-30: __ __ 01 __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    1   0
*2020-05-31: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0

             00    02    04    06    08    10    12    14    16    18    20    22     Out ΔIP
 2020-06-01: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0
 2020-06-02: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0
 2020-06-03: __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __    0   0
 2020-06-04: __ __ __ __ __ __ __ __ __ __ __ __ __ 03 __ __ __ __ __ __                3   1
 ```

The columns represent hours of the day, and the rows represent separate days.
An asterisk in front of a date indicates Sunday.  In each hourly column, `__`
indicates that there were no missed events during that hour.  A number from 1
to 59 indicates the number of missing minutes, and a gap indicates that no data
was received during that hour.

On the right, "Out" indicates the total number of missing minutes in that 24
hour period, and "ΔIP" indicates the number of times the IP address sending
stats changed (aka my external DSL IP).  These tell you a couple of things:

*  If ΔIP matches Out, you probably had that many individual short outages.
*  If ΔIP is smaller than Out, you had at least one outage that was longer than
   a minute.
*  If ΔIP is larger than Out, you had outages that were restored quickly enough
   that no per-minute requests were missed.

From this example, we can quickly learn a few things:

*  On May 23, there was an outage from around 1:30 AM until 7:41 AM.  This was
   actually a power outage at my house, so it was not CenturyLink's fault.
   This demonstrates an important limitation of this monitor: It indicates
   missing data, but doesn't tell you why.  You have to correlate this with
   external events yourself when outages aren't caused by network trouble.
*  On May 25, there was a lot of trouble between 3 AM and 9 AM.  Whatever it
   was had been fixed by 10 AM.
*  It is fairly common to see a brief outage between 3 AM and 4 AM.
*  The connection was nearly perfect from May 28 through Jun 4.  There was a 1
   minute outage on May 30, but no change in IP.  This suggests there was some
   kind of packet loss or brief logging problem on the server rather than a
   line drop.
*  There was a single brief outage on Jun 4.  I was home at the time and
   happened to notice that it happened exactly when lightning hit nearby.  The
   logs themselves don't say why the connection dropped, so this is again
   something that requires you to have some external method to provide the
   explanation.

# Components

## Inside network

The script running inside the network is a basic shell script.  It requires:

* busybox or a similar set of basic utilities
* ash, or similar POSIX-like shell (no bash features are used)
* curl
* cron

The reason to be so restrictive is so that it can run on a low-power device
that is always on.  I run it on my OpenWrt-based router, since that is always
on when my network is on.  Running directly on the router also eliminates the
possibility of a failure in some other network switch or other computer on my
network.

The script attempts to collect stats from the DSL modem and record them
locally.  If you don't have a C1100Z, you'll need to swap this part out or
disable it.  The local logs can be correlated with the external logs to
eliminate/explain some outages, but no scripts to do that automatically are
currently part of the project.  I personally load the local logs into a
postgresql database on my normal desktop machine when I want to do some ad hoc
analysis.

## Outside network

On the outside, the script needs to send requests to a web server that logs in
the apache common log format.  You will need access to those logs.  If you want
to generate and view the stats file shown in the example above, you will also
need cron, perl, and bash on the same web server.

The perl script generates colorized output if you run it on the terminal.
There is also a bash script meant to be run from cron that strips the color
escapes to create a plain text file.

The current setup grabs the last 50k lines out of the apache logs and
re-generates the output file every 10 minutes.  This produces approximately a
two-week lookback on my web server.  You'll want to tune the numbers for your
own activity level.  A straightforward change would be to scrape the logs into
a database and then generate from there instead of directly piping into the
perl script; implementation is left as an exercise for the reader.

## Local analysis

The script running inside the network also generates tab-separated files stored
locally on the modem.  These contain extra information, such as the SNR and
latency.  Here is an example schema that can be used to load them into
postgresql for analysis:

```sql
CREATE TABLE UPLOG (
    timestamp TIMESTAMP,
    ip INET,
    uptime VARCHAR(20),
    kbps_dn INT,
    kbps_up INT,
    snr_dn NUMERIC(5,1),
    snr_up NUMERIC(5,1),
    latency NUMERIC(5,1)
);
```

And then loaded from the psql client like this:

```
DELETE FROM uplog WHERE timestamp >= '2020-05-01' AND timestamp < '2020-06-01';
\copy uplog from /path/to/uplog.202005.csv csv delimiter E'\t' header;
```
