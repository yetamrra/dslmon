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
