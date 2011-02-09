#!/usr/bin/perl

use strict;
use warnings;

sub classes
{
	my $file = shift;
	my @classes;

	open (my $jar, "jar tf $file |") or die $!;
	while (<$jar>) {
		chomp;
		/\$/ and next;
		s/\.class$// or next;
		s/\//./g;
		push @classes, $_;
	}

	\@classes;
}

sub reqfound
{
	my $reqs = shift;

	no warnings qw/uninitialized/;
	#push @$reqs, map { "$_ |$&" } map {
	push @$reqs, map { "$_" } map {
		s/"\[L([^;]+);"/$1/g;
		s/\$.*//;
		s/[\[\]]//g;
		s/\//./g;
		$_;
	} split /,\s*|;[BICJZ\[]*L/, join (",", @_);
	use warnings;
}

sub reqline
{
	$_ = shift;
	my $reqs = shift;

	/\/\/Method ([^\.]+)\.[^:]+:\((L([^\)]+);)?\)/ and reqfound ($reqs, $1, $3);
	/\/\/class ([^\s"]+)$/ and reqfound ($reqs, $1);
	/\/\/Field [^:]+:L([^;]+);$/ and reqfound ($reqs, $1);
	/INSTANCE:L([^\s,;]+)/ and reqfound ($reqs, $1);
	s/\/\/.*//;
	/^(public|protected|private).* ([^\si]+) [^\s\(]+\(([^\)]*)\)/
		and reqfound ($reqs, $2, $3);
	/ extends ([^\s{]+)/ and reqfound ($reqs, $1);
	/ implements ([^\s{]+)/ and reqfound ($reqs, $1);
}

sub requires
{
	my $file = shift;
	my $classes = shift;
	my @requires;

	open (my $dump, "javap -classpath $file -private -c ".
		join (' ', @$classes).' |') or die $!;
	while (<$dump>) {
		chomp;
		reqline ($_, \@requires);
	}

	# Uniq
	[ sort keys %{{ map { $_ => undef } @requires }} ];
}

sub deps
{
	my %files;
	my %provides;
	my %deps;

	# Suck in the requires and provider
	foreach my $filename (@ARGV) {
		my $file = $filename;
		$file =~ s/.*\///;
		$files{$file} = { provides => classes ($filename) };
		$files{$file}->{requires} = requires ($filename,
			$files{$file}->{provides});
	};

	# Index provides
	foreach my $file (keys %files) {
		foreach my $provide (@{$files{$file}->{provides}}) {
			$provides{$provide} ||= [];
			push @{$provides{$provide}}, $file;
		}
	}

	# Resolve requires
	foreach my $file (keys %files) {
		# Empty ones
		$deps{$file} = [];
		foreach my $require (@{$files{$file}->{requires}}) {
			my $providers = $provides{$require};
			push @{$deps{$file}}, @$providers if $providers;
		}
		# Skip redundant and selves
		$deps{$file} = [ grep { $_ ne $file }
			sort keys %{{ map { $_ => undef } @{$deps{$file}} }} ];
	}

	return \%deps;
}

sub graphviz
{
	my $deps = shift;

	print "digraph g {\n";
	print "\tsize=\"50\";\n";
	foreach my $from (keys %$deps) {
		print "\t\"$from\";\n" unless @{$deps->{$from}};
		foreach my $to (@{$deps->{$from}}) {
			print "\t\"$from\" -> \"$to\";\n";
		}
	}
	print "}\n";
}

my $deps = deps;
graphviz ($deps);
