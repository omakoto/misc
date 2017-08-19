package ShellHelper;

use MCommon;

require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(escape parse);

sub escape_word {
  my ($arg) = @_;
  if ( $arg =~ /[^a-zA-Z0-9\-\.\_\/\:\+\@]/ ) {
      return("'" . ($arg =~ s/'/'\\''/gr) . "'"); #/
  } else {
      return($arg);
  }
}

sub escape {
  return join(' ', map { escape_word($_); } @_);
}

sub parse {
  my ($line, $pos) = @_;
  $pos //= length $line;
  my $this = {};

  $this->{pos} = $pos;
  $this->{tokens} = [ split(' ', $line) ];

  bless $this, ShellHelper;
  return $this;
}


sub rebuild {
  my ($this) = @_;

  return escape(@{$this->{tokens}});
}



1;
