#to stop 10 threads from spamming stderr with network errors
my Lock $nospam.=new;
#die with dignity
sub dwd($msg, $file, $line) is export {
    $nospam.protect({
        note "\n--------------------\nperl6uster has died.";
        note 'version: '~::('$VERSION');
        note "file: $file";
        note "line: $line\n";
        note $msg;
        exit 1;
    });
}

#used to align things in PrintConfig() methods
sub spc(Str $s) is export { $s~(' 'x (17-$s.chars)) }

#generate a poor man's UUID for finding wildcard responses
sub wildstr() is export {
    my @a;
    for ^16 {sprintf("%02x",255.rand.Int)==>@a}
    return @a.join;
}

our $domlabel = /^<[a..z0..9A..Z \- \. ]>**0..62 <[a..z0..9A..Z]>$/;

#some constants for doing terminal stuff
constant \esc = qb[\e];
constant \nl = esc~"E";
constant \ris = esc~"c"; #Reset
constant \ht = "\0x09";
constant \csi = qb{\e[};
constant \bold = qb{\e[ 1 m}; #bold ON
constant \BOLD = qb{\e[ 22 m}; # bold OFF
constant \cl = qb{\e[2K}; #erase line
constant \stl = qb{\e[1G}; #move to start of line
