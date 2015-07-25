#!/usr/bin/perl -w

use FindBin qw($Bin);
use strict;
use Encode;
use Data::Dumper;

binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my @langs = @ARGV;
my $l1 = $ARGV[0];

if (scalar(@langs) < 2)
{
  print "usage: $0 langcode1 langcode2 [...]\n";
  exit 1;
}

#chdir($Bin);
my $dir = "txt";
my $outdir = "aligned";
my $preprocessor = "$Bin/tools/split-sentences.perl -q";

print("PWD: " . `pwd`);

foreach my $lang(@langs)
{
  die "No dir $dir/$lang" unless -e "$dir/$lang";
}

my $tuplecode = join('-', @langs);

foreach my $lang(@langs)
{
  print "mkdir -p $outdir/$tuplecode/$lang\n";
  `mkdir -p $outdir/$tuplecode/$lang`;
}

my ($dayfile,$s1); # globals for reporting reasons
open(LS,"ls $dir/$l1|");
while($dayfile = <LS>) {
  chop($dayfile);
  my $align = 1;
  print "aligning: $dayfile\n";
  foreach my $lang (@langs[1..$#langs])
  {
    if (! -e "$dir/$lang/$dayfile") {
      print "$dayfile only for $l1, not $lang, skipping\n";
      $align = 0;
      last;
    }
  }
  if ($align)
  {
    &align();
  }
}

sub align {
  my @TXTnative = ();
  my @TXT = ();
  foreach my $lang (@langs)
  {
    push @TXTnative, [`$preprocessor -l $lang < $dir/$lang/$dayfile`];
  }

  #change perl encoding
  foreach my $native (@TXTnative)
  {
    my $txt = [];
    foreach my $line (@$native) {
      push @$txt, decode_utf8($line);
    }
    push @TXT, $txt;
  }

  my @OUT = ();
  foreach my $lang (@langs)
  {
    my $i = scalar(@OUT);
    open($OUT[$i], ">$outdir/$tuplecode/$lang/$dayfile");
    binmode($OUT[$i], ":utf8");
  }

  my @linenum = ( 0 ) x @langs;
  LOOP: while ( 1 )
  {
    for (my $i = 0; $i <= $#langs; $i++)
    {
      if ($linenum[$i] >= scalar(@{$TXT[$i]}))
      {
        last LOOP;
      }
    }
    # match chapter start
    if ($TXT[0][$linenum[0]] =~ /^<CHAPTER ID=\"?(\d+)\"?/)
    {
      my @chapters = ($1);
      my $maxid = $1;
      my $chapall = 1;
      print "CHAPTER[0]: $1\n";
      for (my $i = 1; $i <= $#langs; $i++) {
        if ($TXT[$i][$linenum[$i]] =~ /^<CHAPTER ID=\"?(\d+)\"?/)
        {
          push @chapters, $1;
          if ($1 > $maxid) { $maxid = $1; }
        }
        else
        {
          $linenum[$i] = &skip($TXT[$i], $linenum[$i], '^<CHAPTER ID=\"?\d+\"?');
          $chapall = 0;
        }
      }
      if ($chapall)
      {
        my $sameid = 1;
        for (my $i = 0; $i <= $#langs; $i++)
        {
          if ($chapters[$i] < $maxid)
          {
            $sameid = 0;
            $linenum[$i] = &skip($TXT[$i], $linenum[$i]+1, '^<CHAPTER ID=\"?\d+\"?');
          }
        }
        if ($sameid)
        {
          for (my $i = 0; $i <= $#langs; $i++)
          {
            print $TXT[$i][$linenum[$i]]."\n";
            print { $OUT[$i] } $TXT[$i][$linenum[$i]++];
          }
        }
      }
    }
    # match speaker start
    elsif ($TXT[0][$linenum[0]] =~ /^<SPEAKER ID=\"?(\d+)\"?/)
    {
      $s1 = $1;
      my @speakers = ($1);
      my $maxid = $1;
      my $speakall = 1;
      print "SPEAKER[0]: $1\n";
      for (my $i = 1; $i <= $#langs; $i++)
      {
        if ($TXT[$i][$linenum[$i]] =~ /^<SPEAKER ID=\"?(\d+)\"?/)
        {
          push @speakers, $1;
          if ($1 > $maxid) { $maxid = $1; }
        }
        else
        {
          $linenum[$i] = &skip($TXT[$i], $linenum[$i], '^<SPEAKER ID=\"?\d+\"?');
          $speakall = 0;
        }
      }
      if ($speakall)
      {
        my $sameid = 1;
        for (my $i = 0; $i <= $#langs; $i++)
        {
          if ($speakers[$i] < $maxid)
          {
            $sameid = 0;
            $linenum[$i] = &skip($TXT[$i], $linenum[$i]+1, '^<SPEAKER ID=\"?\d+\"?');
          }
        }
        if ($sameid)
        {
          for (my $i = 0; $i <= $#langs; $i++)
          {
            print { $OUT[$i] } $TXT[$i][$linenum[$i]++];
          }
        }
      }
    }
    else
    {
      print "processing... @linenum\n";
      my @P;
      my $samelen = 1;
      for (my $i = 0; $i <= $#langs; $i++)
      {
        push @P, [ &extract_paragraph($TXT[$i], \$linenum[$i]) ];
      }
      for (my $i = 1; $i <= $#langs; $i++)
      {
        if (scalar(@{$P[0]}) != scalar(@{$P[$i]}))
        {
          print "$dayfile (speaker $s1) different number of paragraphs ".scalar(@{$P[0]})." != ".scalar(@{$P[$i]})."\n";
          $samelen = 0;
          last;
        }
      }
      if ($samelen) {
        for (my $p = 0; $p <= $#P; $p++)
        {
          if (! $P[0][$p]) { next; }
          my @ALIGNED;
          for (my $i = 1; $i <= $#langs; $i++)
          {
            my @aligned = &sentence_align($P[0][$p], $P[$i][$p]);
            if ($i == 1) {
              @ALIGNED = @aligned;
            }
            else
            {
              my @MERGED;
              for (my $j = 0; $j <= $#ALIGNED; $j++)
              {
                for (my $k = 0; $k <= $#aligned; $k++)
                {
                  if ($ALIGNED[$j][0] eq $aligned[$k][0])
                  {
                    my $align = $ALIGNED[$j];
                    push @$align, $aligned[$k][1];
                    push @MERGED, $align;
                    last;
                  }
                }
              }
              @ALIGNED = @MERGED;
            }
#print "ALIGNED$i: @ALIGNED\n";
#print "ALIGNED$i: ";
#print Dumper @ALIGNED;
          }
          for (my $i = 0; $i <= $#ALIGNED; $i++)
          {
            for (my $j = 0; $j <= $#langs; $j++)
            {
#              print $ALIGNED[$i][$j]."\n";
              print { $OUT[$j] } $ALIGNED[$i][$j]."\n";
            }
          }
        }
      }
    }
  }
}

close(LS);

sub skip {
  my ($TXT,$i,$pattern) = @_;
  my $i_old = $i;
  while($i < scalar(@{$TXT}) && $$TXT[$i] !~ /$pattern/)
  {
    $i++;
  }
  print "$dayfile skipped lines $i_old-$i to reach '$pattern'\n";
  return $i;
}

sub extract_paragraph {
  my ($TXT,$i) = @_;
  my @P = ();
  my $p=0;
  for(;$$i<scalar(@{$TXT}) 
      && ${$TXT}[$$i] !~ /^<SPEAKER ID=\"?\d+\"?/
      && ${$TXT}[$$i] !~ /^<CHAPTER ID=\"?\d+\"?/;$$i++)
  {
    if (${$TXT}[$$i] =~ /^<P>/) {
      $p++ if $P[$p];
      # each XML tag has its own paragraph
      push @{$P[$p]}, ${$TXT}[$$i];
      $p++;
    }
    else {
      push @{$P[$p]}, ${$TXT}[$$i];
    }
  }
  return @P;
}

# this is a vanilla implementation of church and gale
sub sentence_align {
  my ($P1,$P2) = @_;
  chomp(@{$P1});
  chomp(@{$P2});
#print "\@\$P1: ";
#print Dumper @$P1;

  # parameters
  my %PRIOR;
  $PRIOR{1}{1} = 0.89;
  $PRIOR{1}{0} = 0.01/2;
  $PRIOR{0}{1} = 0.01/2;
  $PRIOR{2}{1} = 0.089/2;
  $PRIOR{1}{2} = 0.089/2;
#  $PRIOR{2}{2} = 0.011;
  
  # compute length (in characters)
  my (@LEN1,@LEN2);
  $LEN1[0] = 0;
  for(my $i=0;$i<scalar(@{$P1});$i++) {
    my $line = $$P1[$i];
    $line =~ s/[\s\r\n]+//g;
#    print "1: $line\n";
    $LEN1[$i+1] = $LEN1[$i] + length($line);
  }
  $LEN2[0] = 0;
  for(my $i=0;$i<scalar(@{$P2});$i++) {
    my $line = $$P2[$i];
    $line =~ s/[\s\r\n]+//g;
#    print "2: $line\n";
    $LEN2[$i+1] = $LEN2[$i] + length($line);
  }

  # dynamic programming
  my (@COST,@BACK);
  $COST[0][0] = 0;
  for(my $i1=0;$i1<=scalar(@{$P1});$i1++) {
    for(my $i2=0;$i2<=scalar(@{$P2});$i2++) {
      next if $i1 + $i2 == 0;
      $COST[$i1][$i2] = 1e10;
      foreach my $d1 (keys %PRIOR) {
	next if $d1>$i1;
	foreach my $d2 (keys %{$PRIOR{$d1}}) {
	  next if $d2>$i2;
	  my $cost = $COST[$i1-$d1][$i2-$d2] - log($PRIOR{$d1}{$d2}) +  
	    &match($LEN1[$i1]-$LEN1[$i1-$d1], $LEN2[$i2]-$LEN2[$i2-$d2]);
#	  print "($i1->".($i1-$d1).",$i2->".($i2-$d2).") [".($LEN1[$i1]-$LEN1[$i1-$d1]).",".($LEN2[$i2]-$LEN2[$i2-$d2])."] = $COST[$i1-$d1][$i2-$d2] - ".log($PRIOR{$d1}{$d2})." + ".&match($LEN1[$i1]-$LEN1[$i1-$d1], $LEN2[$i2]-$LEN2[$i2-$d2])." = $cost\n";
	  if ($cost < $COST[$i1][$i2]) {
	    $COST[$i1][$i2] = $cost;
	    @{$BACK[$i1][$i2]} = ($i1-$d1,$i2-$d2);
	  }
	}
      }
#      print $COST[$i1][$i2]."($i1-$BACK[$i1][$i2][0],$i2-$BACK[$i1][$i2][1]) ";
    }
#    print "\n";
  }
  
  # back tracking
  my (%NEXT);
  my $i1 = scalar(@{$P1});
  my $i2 = scalar(@{$P2});
  while($i1>0 || $i2>0) {
#    print "back $i1 $i2\n";
    @{$NEXT{$BACK[$i1][$i2][0]}{$BACK[$i1][$i2][1]}} = ($i1,$i2);
    ($i1,$i2) = ($BACK[$i1][$i2][0],$BACK[$i1][$i2][1]);
  }

  my @aligned = ();
  while($i1<scalar(@{$P1}) || $i2<scalar(@{$P2})) {
#    print "fwd $i1 $i2\n";
    push @aligned, ["",""];
    for(my $i=$i1;$i<$NEXT{$i1}{$i2}[0];$i++) {
      $aligned[$#aligned][0] .= " " unless $i == $i1;
      $aligned[$#aligned][0] .= $$P1[$i];
    }
    for(my $i=$i2;$i<$NEXT{$i1}{$i2}[1];$i++) {
      $aligned[$#aligned][1] .= " " unless $i == $i2;
      $aligned[$#aligned][1] .= $$P2[$i];
    }
    ($i1,$i2) = @{$NEXT{$i1}{$i2}};
#print Dumper @aligned;
  }
  return @aligned;
}


sub match {
  my ($len1,$len2) = @_;
  my $c = 1;
  my $s2 = 6.8;

  if ($len1==0 && $len2==0) { return 0; }
  my $mean = ($len1 + $len2/$c) / 2;
  my $z = ($c * $len1 - $len2)/sqrt($s2 * $mean);
  if ($z < 0) { $z = -$z; }
  my $pd = 2 * (1 - &pnorm($z));
  if ($pd>0) { return -log($pd); }
  return 25;
}

sub pnorm {
  my ($z) = @_;
  my $t = 1/(1 + 0.2316419 * $z);
  return 1 - 0.3989423 * exp(-$z * $z / 2) *
    ((((1.330274429 * $t 
	- 1.821255978) * $t 
       + 1.781477937) * $t 
      - 0.356563782) * $t
     + 0.319381530) * $t;
}

