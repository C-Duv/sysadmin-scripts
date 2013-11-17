#!/usr/bin/perl

##
# Invert the order of a certficate chain
# 
# Version 0.0.1    DUVERGIER Claude (http://claude.duvergier.fr)
# 
# Licence : GNU General Public License v3 (GPL-3)
# 
# Inspired by :
# http://gagravarr.org/code/cert-split.pl v0.0.1 (Nick Burch <nick@tirian.magd.ox.ac.uk>)
##

my $filename = shift;
unless($filename) {
    die("Usage:\n cert-invertchain.pl <chain-certificate-file>\n");
}

open INP, "<$filename" or die("Unable to load \"$filename\"\n");

my $ifile = "";
my $thisfile = "";
my $invertedfile = "";
while(<INP>) { 
    $ifile .= $_; 
    $thisfile .= $_;
    if($_ =~ /^\-+END(\s\w+)?\sCERTIFICATE\-+$/) {
        $invertedfile = $thisfile . $invertedfile;
        $thisfile = "";
    }
}
close INP;

print $invertedfile;
