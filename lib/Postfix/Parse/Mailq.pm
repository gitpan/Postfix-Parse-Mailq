use strict;
use warnings;
package Postfix::Parse::Mailq;
# ABSTRACT: parse the output of the postfix mailq command
$Postfix::Parse::Mailq::VERSION = '1.004';
use Mixin::Linewise::Readers -readers;

# =head1 SYNOPSIS
#
#   use Postfix::Parse::Mailq;
#
#   my $mailq_output = `mailq`;
#   my $entries = Postfix::Parse::Mailq->read_string($mailq_output);
#
#   my $bytes = 0;
#   for my $entry (@$entries) {
#     next unless grep { /\@aol.com$/ } @{ $entry->{remaining_rcpts} };
#     $bytes += $entry->{size};
#   }
#   
#   print "$bytes bytes remain to send to AOL destinations\n";
#
# =head1 WARNING
#
# This code is really rough and the interface will change.  Entries will be
# objects.  There will be some more methods.  Still, the basics are likely to
# keep working, or keep pretty close to what you see here now.
#
# =method read_file
#
# =method read_handle
#
# =method read_string
#
#   my $entries = Postfix::Parse::Mailq->read_string($string, \%arg);
#
# This methods read the output of postfix's F<mailq> from a file (by name), a
# filehandle, or a string, respectively.  They return an arrayref of hashrefs,
# each hashref representing one entry in the queue as reported by F<mailq>.
#
# Valid arguments are:
#
#   spool - a hashref of { queue_id -> spool_name } pairs
#           if given, this will be used to attempt to indicate in which
#           spool messages currently are; it is not entirely reliable (race!)
#
# =cut

sub read_handle {
  my ($self, $handle, $arg) = @_;
  $arg ||= {};
  $arg->{spool} ||= {};

  my $first = $handle->getline;

  chomp $first;
  return [] if $first eq 'Mail queue is empty';

  Carp::confess("first line did not appear to be first line of mailq output")
    unless $first =~ m{\A-+Queue ID-+};

  my @current;
  my @entries;
  LINE: while (my $line = $handle->getline) {
    if ($line eq "\n") {
      my $entry = $self->parse_block(\@current);
      $entry->{spool} = $arg->{spool}{ $entry->{queue_id} } if $arg->{spool};
      push @entries, $entry;
      @current = ();
      next LINE;
    }

    push @current, $line;
  }

  if (@current and $current[0] !~ /^-- \d+ .?bytes/i) {
    my $entry = $self->parse_block(\@current);
    $entry->{spool} = $arg->{spool}{ $entry->{queue_id} } if $arg->{spool};
    push @entries, $entry;
  }

  return \@entries;
}

# =method parse_block
#
#   my $entry = Mailq->parse_block(\@lines);
#
# Given all the lines in a single entry's block of lines in mailq output, this
# returns data about the entry.
#
# =cut

my %STATUS_FOR = (
  '!' => 'held',
  '*' => 'active',
);

sub parse_block {
  my ($self, $block) = @_;

  chomp @$block;
  my $first = shift @$block;
  my $error = defined $block->[0] && $block->[0] =~ /\A\S/
            ? (shift @$block)
            : undef;
  my @dest  = map { s/^\s+//; $_; } @$block;

  my ($qid, $status_chr, $size, $date, $sender) = $first =~ m/
    \A
    ([A-F0-9]+|[0-9B-Zb-z]+)
    ([*!])?
    \s+
    (\d+)
    \s+
    (.{19})
    \s+
    (\S.+)
    \z
  /x;

  my $status = $status_chr ? ($STATUS_FOR{$status_chr} || 'unknown') : 'queued';

  return {
    queue_id        => $qid,
    status          => $status,
    size            => $size,
    date            => $date,
    sender          => $sender,
    error_string    => $error,
    remaining_rcpts => \@dest,
  }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Postfix::Parse::Mailq - parse the output of the postfix mailq command

=head1 VERSION

version 1.004

=head1 SYNOPSIS

  use Postfix::Parse::Mailq;

  my $mailq_output = `mailq`;
  my $entries = Postfix::Parse::Mailq->read_string($mailq_output);

  my $bytes = 0;
  for my $entry (@$entries) {
    next unless grep { /\@aol.com$/ } @{ $entry->{remaining_rcpts} };
    $bytes += $entry->{size};
  }
  
  print "$bytes bytes remain to send to AOL destinations\n";

=head1 METHODS

=head2 read_file

=head2 read_handle

=head2 read_string

  my $entries = Postfix::Parse::Mailq->read_string($string, \%arg);

This methods read the output of postfix's F<mailq> from a file (by name), a
filehandle, or a string, respectively.  They return an arrayref of hashrefs,
each hashref representing one entry in the queue as reported by F<mailq>.

Valid arguments are:

  spool - a hashref of { queue_id -> spool_name } pairs
          if given, this will be used to attempt to indicate in which
          spool messages currently are; it is not entirely reliable (race!)

=head2 parse_block

  my $entry = Mailq->parse_block(\@lines);

Given all the lines in a single entry's block of lines in mailq output, this
returns data about the entry.

=head1 WARNING

This code is really rough and the interface will change.  Entries will be
objects.  There will be some more methods.  Still, the basics are likely to
keep working, or keep pretty close to what you see here now.

=head1 AUTHOR

Ricardo SIGNES <rjbs@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Ricardo SIGNES.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
