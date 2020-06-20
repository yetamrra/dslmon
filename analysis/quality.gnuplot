set datafile separator ","
set xdata time
set timefmt "%Y-%m-%dT%H:%M:%S"
set yrange [0.0:25.0]
set xrange [ARG2:ARG3]
set grid
set key top left
set terminal png size 1000,500

plot ARG1 using 1:2 with lines title "Outage", \
     ARG1 using 1:5 with lines title "SNR Dn (dB)", \
     ARG1 using 1:6 with lines title "SNR Up (dB)", \
     ARG1 using 1:($3/1000) with lines title "Speed Dn (Mbps)", \
     ARG1 using 1:($4/1000) with lines title "Speed Up (Mbps)"

