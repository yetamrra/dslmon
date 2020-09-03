#!/usr/bin/perl
# SPDX-License-Identifier: GPL-2.0-or-later

# Copyright 2020 Benjamin Gordon.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use warnings;
use strict;
use Data::Dumper;
use DateTime;
use List::Util qw(sum);
use Tie::IxHash;
use Term::ANSIColor;

sub outFmt {
    my $val = shift;

    if (!$val) {
        return "  ";
    }
    if ($val == 60) {
        return "__";
    }
    if ($val > 55) {
        return color('yellow') . sprintf("%02d", 60-$val) . color('reset');
    } else {
        return color('red') . sprintf("%02d", 60-$val) . color('reset');
    }
}

sub dateKey {
    my $ts = shift;
    my $date;
    if ($ts->day_of_week == 7) {
        $date = '*';
    } else {
        $date = ' ';
    }
    $date .= $ts->ymd;
    return $date;
}

tie my %checkins, 'Tie::IxHash';
my $first = "";
my $ts;
my $lastIP = '';
my $lastIPChange;
my $firstTS;
my $bwdn;
my $bwup;
my $lineup;
while (<>) {
    if (! m-(?<ip>[\d.]+).*/uplog.txt\?(?<year>\d{4})(?<month>\d{2})(?<day>\d{2})(?<hour>\d{2})(?<min>\d{2})(?<sec>\d{2})(?:&d=(?<bwdn>\d+)&u=(?<bwup>\d+)&t=(?<uptime>[\d:]+))?-) {
        next;
    }
    my $ip = $+{ip};
    $bwdn = $+{bwdn} || '';
    $bwup = $+{bwup} || '';
    $lineup = $+{uptime} || '';

    # Skip past first partial day.
    if (!$first) {
        $first = "$+{year}$+{month}$+{day}";
    }
    if ("$+{year}$+{month}$+{day}" eq $first) {
        $lastIP = $ip;
        next;
    }

    $ts = DateTime->new(
        year => $+{year},
        month => $+{month},
        day => $+{day},
        hour => $+{hour},
        minute => $+{min},
        second => $+{sec},
        time_zone => 'America/Denver'
    );
    if (!$firstTS) {
        $firstTS = $ts;
    }

    my $date = dateKey($ts);

    if (!defined $checkins{$date}) {
        $checkins{$date} = {
            checkins => {},
            minutes => {},
            ips => {},
            newips => 0,
        };
        tie %{$checkins{$date}->{checkins}}, 'Tie::IxHash';
        foreach my $h ( 0..23) {
            $checkins{$date}->{checkins}->{$h} = 0;
            $checkins{$date}->{minutes}->{$h} = {};
        }
    }
    $checkins{$date}->{minutes}->{$ts->hour}->{$ts->minute}++;
    $checkins{$date}->{ips}->{$ip} = 1;
    if ($ip ne $lastIP) {
        $checkins{$date}->{newips}++;
        $lastIP = $ip;
        $lastIPChange = $ts->clone();
    }
}

# Add up hourly checkins
foreach my $day(keys %checkins) {
    for (my $h=0; $h<24; $h++) {
        $checkins{$day}->{checkins}->{$h} = scalar(keys %{$checkins{$day}->{minutes}->{$h}});
    }
}

# Clean up hours past current time.
my $lastDate = dateKey($ts);
$checkins{$lastDate}->{checkins}->{$ts->hour} += 59 - $ts->minute;
for (my $h = $ts->hour+1; $h<24; $h++) {
    $checkins{$lastDate}->{checkins}->{$h} += 60;
}

$lastIPChange = $firstTS if !$lastIPChange;
my $uptime = $lastIPChange->delta_ms($ts);
my ($up_h, $up_m) = $uptime->in_units('hours', 'minutes');
my $up_d = '';
if ($up_h > 47) {
    $up_d = sprintf("%dd", int($up_h / 24));
    $up_h = $up_h % 24;
}

print sprintf("Last checkin: %s %s\n", $ts->ymd, $ts->hms);
print sprintf("Last IP change: %s %s (up %s%dh%02dm)\n", $lastIPChange->ymd, $lastIPChange->hms, $up_d, $up_h, $up_m);
print sprintf("Last speed: %s/%s\n", $bwdn, $bwup);
print sprintf("Last uptime: %s\n", $lineup);

$first = 1;
foreach my $day (keys %checkins) {
    if ($first || $day =~ m/01$/) {
        print "\n             00    02    04    06    08    10    12    14    16    18    20    22     Out ΔIP\n";
        $first = 0;
    }

    my $line = '';
    my @checks = values %{$checkins{$day}->{checkins}};
    if ($day ne $lastDate) {
        $line = join(' ', map { outFmt($_) } @checks );
    } else {
        for (my $h=0; $h<24; $h++) {
            if ($h <= $ts->hour) {
                $line .= outFmt($checks[$h]) . ' ';
            } else {
                $line .= '   ';
            }
        }
        chop $line;
    }
    $line .=  sprintf(" %4d", 1440-sum(@checks));
    $line .=  sprintf(" %3d", $checkins{$day}->{newips});

    print "$day: $line\n";
}
