my %cache = ();

sub isfile {
  my ($file) = @_;

  if (!exists($cache{$file})) {
    $cache{$file} = -e $file;
  }
  return $cache{$file};
}

1;
