# Provide isfile($) function, which tells if a given file exists,
# with a cache.

my %cache = ();

sub isfile($) {
  my ($file) = @_;

  if (!exists($cache{$file})) {
    $cache{$file} = -e $file;
  }
  return $cache{$file};
}

sub clear_file_cache() {
  %cache = ();
}

1;
