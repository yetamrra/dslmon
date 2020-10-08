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
use Apache::Log::Parser;
use DBI;
use Time::Piece;
use Time::Seconds qw( ONE_MINUTE );

if (scalar(@ARGV) < 1) {
    die "Usage: $0 config logfile logfile ...";
}

my $config = shift;
my %config = ();
open my $fh, '<', $config or die "Unable to open config file $config";
while (<$fh>) {
    chomp;
    s/^\s*//;
    s/\s*$//;
    next if m/^#/;
    my ($k, $v) = split /\s*=\s*/, $_, 2;
    $config{lc $k} = $v;
}
close($fh);

my $parser = Apache::Log::Parser->new(fast => 1);
my $dbh = DBI->connect("dbi:Pg:dbname=$config{dbname}", $config{dbuser}, $config{dbpass}, {AutoCommit => 0});
my $ins = $dbh->prepare(q{INSERT INTO uplog (logtime, dsltime, ip, uptime, kbps_dn, kbps_up)
                                 VALUES (?,?,?,?,?,?)
                                 ON CONFLICT (logtime) DO NOTHING});

# Find the latest date previously logged.  This allows us to redo a small
# overlap instead of attempting to re-insert the entire log file.
my ($logend) = $dbh->selectrow_array("SELECT TO_CHAR(MAX(logtime), 'YYYY-MM-DD HH24:MI:SSTZHTZM') FROM uplog");
$logend = '1999-01-01 00:00:00-0000' if !$logend;
$logend = Time::Piece->strptime($logend, '%Y-%m-%d %H:%M:%S%z');
my $start = $logend - ONE_MINUTE * $config{logoverlap};

my $rows = 0;
while (<>) {
    chomp;
    my $entry = $parser->parse($_);

    next if (!$entry->{path});

    my $logtime = Time::Piece->strptime($entry->{datetime}, '%d/%b/%Y:%H:%M:%S %z');
    next if ($logtime < $start);

    next if ($entry->{path} !~ m{
            ^/uplog.txt\?
            (?<year>\d{4})(?<month>\d{2})(?<day>\d{2})(?<hour>\d{2})(?<min>\d{2})(?<sec>\d{2})
            (?:
                &d=(?<bwdn>\d+)
                &u=(?<bwup>\d+)
                &t=(?<uptime>[\d:]+)
            )?
        }x);

    my $dsltime = "$+{year}-$+{month}-$+{day} $+{hour}:$+{min}:$+{sec}";
    $rows += $ins->execute($entry->{datetime}, $dsltime, $entry->{rhost}, $+{uptime}, $+{bwdn}, $+{bwup});
}

$dbh->commit();
$dbh->disconnect();
say "$rows new rows inserted." if -t STDOUT;
