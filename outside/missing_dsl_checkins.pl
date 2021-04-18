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

use v5.10;
use warnings;
use strict;
use Data::Dumper;
use DateTime;
use DBI;
use Getopt::Long;
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

sub updateArrow {
    my $cur = \$_[0];
    my $new = $_[1];

    if ($$cur eq ' ') {
        $$cur = $new;
    } elsif ($$cur ne $new) {
        $$cur = '↕';
    }
}

my $config;
my $days = 31;
my $reverse;
my $speed;
GetOptions(
    'config=s' => \$config,
    'days=i' => \$days,
    'reverse' => \$reverse,
    'speed' => \$speed,
);
die "Usage: $0 --config=/path/to/config [--days=NN] [--reverse]\n" if !$config;

my %config = ();
open my $fh, '<', $config or die "Unable to open config file $config\n";
while (<$fh>) {
    chomp;
    s/^\s*//;
    s/\s*$//;
    next if m/^#/;
    my ($k, $v) = split /\s*=\s*/, $_, 2;
    $config{lc $k} = $v;
}
close($fh);

tie my %checkins, 'Tie::IxHash';
my $first = "";
my $ts;
my $lastIP = '';
my $lastIPChange;
my $firstTS;
my $bwdn;
my $bwup;
my $lineup;
my $tz = $ENV{TZ} || 'America/Denver';

my $dbh = DBI->connect("dbi:Pg:dbname=$config{dbname}", $config{dbuser}, $config{dbpass}, {RaiseError => 1});
$dbh->do('SET timezone TO ?', undef, $tz);
my $sth = $dbh->prepare(q{SELECT ip,
                                 extract(year from logtime), extract(month from logtime),
                                 extract(day from logtime), extract(hour from logtime),
                                 extract(minute from logtime), extract(second from logtime),
                                 kbps_dn, kbps_up, uptime
                          FROM uplog
                          WHERE logtime >= current_date - ? * interval '1 day'
                          ORDER BY logtime});
$sth->execute("$days");
while (my @row = $sth->fetchrow_array()) {
    my ($ip, $year, $month, $day, $hour, $min, $sec);
    ($ip, $year, $month, $day, $hour, $min, $sec, $bwdn, $bwup, $lineup) = @row;

    # Skip past first partial day.
    if (!$first) {
        $first = "${year}${month}${day}";
    }
    if ("${year}${month}${day}" eq $first) {
        $lastIP = $ip;
        next;
    }

    $ts = DateTime->new(
        year => $year,
        month => $month,
        day => $day,
        hour => $hour,
        minute => $min,
        second => $sec,
        time_zone => $tz,
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
            maxdn => $bwdn,
            mindn => $bwdn,
            deltadn => ' ',
            maxup => $bwup,
            minup => $bwup,
            deltaup => ' ',
        };
        tie %{$checkins{$date}->{checkins}}, 'Tie::IxHash';
        foreach my $h ( 0..23) {
            $checkins{$date}->{checkins}->{$h} = 0;
            $checkins{$date}->{minutes}->{$h} = {};
        }
    }
    $checkins{$date}->{minutes}->{$ts->hour}->{$ts->minute}++;
    $checkins{$date}->{ips}->{$ip} = 1;
    if ($bwdn ne '') {
        if ($bwdn > $checkins{$date}->{maxdn}) {
            $checkins{$date}->{maxdn} = $bwdn;
            updateArrow($checkins{$date}->{deltadn}, '↑');
        }
        if ($bwdn < $checkins{$date}->{mindn}) {
            $checkins{$date}->{mindn} = $bwdn;
            updateArrow($checkins{$date}->{deltadn}, '↓');
        }
    }
    if ($bwup ne '') {
        if ($bwup > $checkins{$date}->{maxup}) {
            $checkins{$date}->{maxup} = $bwup;
            updateArrow($checkins{$date}->{deltaup}, '↑');
        }
        if ($bwup < $checkins{$date}->{minup}) {
            $checkins{$date}->{minup} = $bwup;
            updateArrow($checkins{$date}->{deltaup}, '↓');
        }
    }
    if ($ip ne $lastIP) {
        $checkins{$date}->{newips}++;
        $lastIP = $ip;
        $lastIPChange = $ts->clone();
    }
}
$sth->finish();
$dbh->disconnect();

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
my @days = $reverse ? (reverse keys %checkins) : (keys %checkins);
foreach my $day (@days) {
    # Print a header line at the beginning and between months.
    if ($day =~ m/01$/ && !$reverse) {
        $first = 1;
    }
    if ($first) {
        my $header = "\n             00    02    04    06    08    10    12    14    16    18    20    22     Out ΔIP";
        if ($speed) {
            $header .= "     Down       Up";
        }
        say $header;
        $first = 0;
    }
    if ($day =~ m/01$/ && $reverse) {
        # Print header before the next line.
        $first = 1;
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
    if ($speed) {
        $line .=  sprintf(" %9s", sprintf(" %s%.1f/%.1f",
                          $checkins{$day}->{deltadn},
                          $checkins{$day}->{maxdn} / 1000,
                          $checkins{$day}->{mindn} / 1000));
        $line .=  sprintf("  %s%3.1f/%3.1f",
                          $checkins{$day}->{deltaup},
                          $checkins{$day}->{maxup} / 1000,
                          $checkins{$day}->{minup} / 1000);
    }
    say "$day: $line";
}
