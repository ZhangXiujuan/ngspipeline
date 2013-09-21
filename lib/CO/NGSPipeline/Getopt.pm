package CO::NGSPipeline::Getopt;

use strict;
use CO::Utils;
use Getopt::Long;
use File::Basename;
use Data::Dumper;

sub new {
	my $class = shift;
	$class = ref($class) ? ref($class) : $class;
	
	my $pipeline = shift;
	
	my $opt = bless {_before => "",
	                 _after => "",
					 _index => 0,
					 @_}, $class;
	
	$opt->reset_opt;
	
	return $opt;
}

sub before {
	my $opt = shift;
	my $text = shift;
	
	$opt->{_before} = $text;
}

sub after {
	my $opt = shift;
	my $text = shift;
	
	$opt->{_after} = $text;
}

sub reset_opt {
	my $opt = shift;
	
	my $ref0 = \1;
	my $ref1 = \1;
	my $ref2 = \1;
	my $ref3 = \1;
	my $ref4 = \1;
	my $ref5 = \1;
	my $ref6 = \1;
	my $ref7 = \1;
	
	$opt->add($ref0, "help", "print help message and exit");
	$opt->add($ref1, "list=s", "sample list, containing columns which are: 1. fastq file for paired end 1, should be gzipped; 2. fastq file for paired end 2, should be gzipped; 3. sample name. unique 4. if from multiple lanes, whether they come from the same libraries or not. (any type of strings to represent category of libraries, optional. Now it is only workable for WGBS pipeline.)");
	$opt->add($ref2, "dir=s", "working dir, default is `analysis`. Under the working dir, there are list of directories named with sample names which are called job directory for each sample.");
	$opt->add($ref3, "tool=s", "");
	$opt->add($ref4, "sample=s", "subset of sample ids, should seperated by ',' (no blank)");
	$opt->add($ref5, "enforce", "enforce to re-run pipeline from the beginning no matter they were successfully finished or not.");
	$opt->add($ref6, "filesize=i", "If size of some output files (e.g. bam files, methylation calling files) are smaller than this value, then step is terminated. Default is 1M (1024*1024). Set it to zero or non-number strings to shut down file size checking.");
	$opt->add($ref7, "test", "testing mode");
	
	return $opt;
}

sub add {
	my $opt = shift;
	
	my $ref = shift;
	my $param = shift;
	my $desc = shift;
	
	my $name = $param; $name =~s/=.*$//;

	if($opt->{$name}) {
		$opt->{$name}->{'ref'} = $ref;
		$opt->{$name}->{'param'} = $param;
		$opt->{$name}->{'desc'} = $desc if($desc);
	} else {
		$opt->{_index} ++;
		
		$opt->{$name}->{'ref'} = $ref;
		$opt->{$name}->{'param'} = $param;
		$opt->{$name}->{'desc'} = $desc;
		$opt->{$name}->{'index'} = $opt->index;
	}
	
	return $opt;
}

sub del {
	my $opt = shift;
	
	my $name = shift;
	
	delete($opt->{$name});
	return $opt;
}

sub index {
	my $opt = shift;
	
	return $opt->{_index};
}

sub opt_name {
	my $opt = shift;
	
	grep {! /^_/} keys %$opt;
}

sub help_msg {
	my $opt = shift;
	
	print $opt->{_before} if($opt->{_before});
	
	my $max_name_len = 0;
	foreach my $name ($opt->opt_name) {
		$max_name_len = length($name) if ($max_name_len < length($name));
	}
	$max_name_len += 5;
	
	print "Parameters:\n\n";
	foreach my $name (sort {$opt->{$a}->{index} <=> $opt->{$b}->{index}} $opt->opt_name) {
		print "  --$name";
		
		my $i_col = length($name) + 4;
		my @words = split " ", $opt->{$name}->{'desc'};
		
		while(my $w = shift @words) {
			if($i_col < $max_name_len) {
				print " " x ($max_name_len - $i_col);
			}
			if($i_col + length($w) > 70) {
				print "\n";
				print " " x $max_name_len;
				print "$w ";
				$i_col = $max_name_len + length($w) + 1;
			} else {
				print "$w ";
				$i_col += length($w) + 1;
			}
		}
		print "\n\n";
		
	}
	
	print $opt->{_after} if($opt->{_after});
}

sub getopt {
	my $opt = shift;
	
	if(scalar(@ARGV) == 0 or grep {/^(-h|--help)$/i} @ARGV) {
		$opt->help_msg();
		exit;
	}
	
	my %param;
	foreach my $name ($opt->opt_name) {
		$param{$opt->{$name}->{'param'}} = $opt->{$name}->{'ref'};
	}
	
	GetOptions(%param) or ($opt->help_msg, exit);
	
	$opt->validate;
}

sub validate {
	my $opt = shift;
	
	my $list_ref = $opt->{'list'}->{'ref'};
	my $wd_ref = $opt->{'dir'}->{'ref'};
	my $request_sampleid_ref = $opt->{'sample'}->{'ref'};
	my $tool_ref = $opt->{'tool'}->{'ref'};
	my $filesize_ref = $opt->{'filesize'}->{'ref'};
	
	
	my %subset_samples = map { $_ => 1} split ",", $$request_sampleid_ref;
	$$filesize_ref += 0;

	open F, $$list_ref or die "Cannot open $$list_ref\n";
	my $r1;
	my $r2;
	my $sample;
	my $n_sample = 0;
	while(my $line = <F>) {
		chomp $line;
		next if($line =~/^\s*$/);
		next if($line =~/^#/);
		
		my @tmp = split "\t", $line;
		$tmp[0] = to_abs_path($tmp[0]);
		$tmp[1] = to_abs_path($tmp[1]);
		
		if(basename($tmp[0]) eq basename($tmp[1])) {
			die "two fastq files have same names! check your file\n";
		}
		
		if(scalar(%subset_samples) and !$subset_samples{$tmp[2]}) {
			print "$tmp[2] is not in --sample, skip this sample.\n";
			next;
		}
		
		# if no record for this sample, initialize the array reference
		if(! defined($sample->{$tmp[2]})) {
			$sample->{$tmp[2]} = {};
			$sample->{$tmp[2]}->{r1} = [];
			$sample->{$tmp[2]}->{r2} = [];
			$sample->{$tmp[2]}->{library} = [];
		}
		
		push(@{$sample->{$tmp[2]}->{r1}}, $tmp[0]);
		push(@{$sample->{$tmp[2]}->{r2}}, $tmp[1]);
		
		# currently do not support multiple libraries for a same sample
		push(@{$sample->{$tmp[2]}->{library}}, defined($tmp[3]) ? $tmp[3] : undef);
		
		$n_sample ++;
	}

	$$wd_ref = to_abs_path($$wd_ref);
	# seems set mode of the dir to 0755 not always successful
	-e $$wd_ref ? 1: mkdir $$wd_ref, 0775 || die "cannto create dir: $$wd_ref with mode 0775\n";
	
	$$tool_ref = lc($$tool_ref);
	
	print "Working directory is $$wd_ref.\n";
	print "Totally $n_sample samples with ". scalar(keys %$sample)." unique sample ids \n";
	print "Using $$tool_ref.\n\n";

	$$list_ref = $sample;
}

1;