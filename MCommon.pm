
$ENV{FILE_RE_CHARS} = "A-Za-z0-9\-\,\.\/\%\_\+\@\~\$\{\}" unless $ENV{FILE_RE_CHARS};

sub validate_keys {
  my ($source, @valid_keys) = @_;

  my %hash = (%$source);

  for my $k (@valid_keys) {
    delete $hash{$k};
  }
  if (%hash) {
    die("Invalid keys: " . join(", ", keys(%hash)) . "\n");
  }
}
