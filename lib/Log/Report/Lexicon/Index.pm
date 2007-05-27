
package Log::Report::Lexicon::Index;

use warnings;
use strict;

use File::Find  ();

use Log::Report 'log-report', syntax => 'SHORT';
use Log::Report::Util  qw/parse_locale/;

=chapter NAME
Log::Report::Lexicon::Index - search through available translation files

=chapter SYNOPSIS
 my $index = Log::Report::Lexicon::Index->new($directory);
 my $fn    = $index->find('my-domain', 'nl-NL.utf-8');

=chapter DESCRIPTION
This module handles the lookup of translation files for a whole
directory tree.  It is lazy loading, which means that it will only
build the search tree when addressed, not when the object is
created.

=chapter METHODS

=section Constructors

=c_method new DIRECTORY, OPTIONS
=cut

sub new($;@)
{   my $class = shift;
    bless {dir => @_}, $class;  # dir before first argument.
}

=section Accessors

=method directory
Returns the directory name.
=cut

sub directory() {shift->{dir}}

=section Search

=method index
For internal use only.
Force the creation of the index (if not already done).  Returns a hash
with key-value pairs, where the key is the lower-cased version of the
filename, and the value the case-sensitive version of the filename.
=cut

sub index() 
{   my $self = shift;
    return $self->{index} if exists $self->{index};

    my $dir       = $self->directory;
    my $strip_dir = qr!\Q$dir/!;

    $self->{index} = {};
    File::Find::find
    ( +{ wanted   => sub
           { -f or return 1;
             (my $key = $_) =~ s/$strip_dir//;
             $self->addFile($key, $_);
             1;
           }
         , follow   => 1, no_chdir => 1
       } , $dir
    );

    $self->{index};
}

=method addFile BASENAME, [ABSOLUTE]
Add a certain file to the index.  This method returns the ABSOLUTE
path to that file, which must be used to access it.  When not explicitly
specified, the ABSOLUTE path will be calculated.
=cut

sub addFile($;$)
{   my ($self, $base, $abs) = @_;
    $abs ||= File::Spec->catfile($self->directory, $base);
    $base =~ s!\\!/!g;  # dos->unix
    $self->{index}{lc $base} = $abs;
}

=method find TEXTDOMAIN, LOCALE
Lookup the best translation table, according to the rules described
in chapter L</DETAILS>, below.

Returned is a filename, or C<undef> if nothing is defined for the
LOCALE (there is no default on this level).

=error illegal locale '$locale'
=cut

# location to work-around platform dependent mutulations.
# may be extended with mo files as well.
sub _find($$) { $_[0]->{"$_[1].po"} }

sub find($$)
{   my $self   = shift;
    my $domain = lc shift;
    my $locale = lc shift;

    my $index = $self->index;
    keys %$index or return undef;

    my ($lang,$terr,$cs,$modif) = parse_locale $locale
        or error "illegal locale '{locale}', when looking for {domain}"
               , locale => $locale, domain => $domain;

    $terr  = defined $terr  ? '_'.$terr  : '';
    $cs    = defined $cs    ? '.'.$cs    : '';
    $modif = defined $modif ? '@'.$modif : '';

    (my $normcs = $cs) =~ s/[^a-z\d]//g;
    $normcs = "iso$normcs"
        if length $normcs && $normcs !~ /\D/;
    $normcs = '.'.$normcs
        if length $normcs;

    my $fn;

    for my $f ("/lc_messages/$domain", "/$domain")
    {   $fn
        ||= _find($index, "$lang$terr$cs$modif$f")
        ||  _find($index, "$lang$terr$normcs$modif$f")
        ||  _find($index, "$lang$terr$modif$f")
        ||  _find($index, "$lang$modif$f")
        ||  _find($index, "$lang$f");
    }

       $fn
    || _find($index, "$domain/$lang$terr$cs$modif")
    || _find($index, "$domain/$lang$terr$normcs$modif")
    || _find($index, "$domain/$lang$terr$modif")
    || _find($index, "$domain/$lang$modif")
    || _find($index, "$domain/$lang");
}

=method list DOMAIN
Returned is a list of filenames which is used to update the list of
MSGIDs when source files have changed.  All translation files which
belong to a certain DOMAIN are listed.

You probably need to filter the filenames further, for instance to reduce
the set to only C<.po> files, get rit of C<mo> files and readme's.
=cut

sub list($)
{   my $self   = shift;
    my $domain = lc shift;
    my $index  = $self->index;

    map { $index->{$_} }
       grep m! ^\Q$domain\E/ | \b\Q$domain\E[^/]*$ !x
          , keys %$index;
}

=chapter DETAILS

It's always complicated to find the lexicon files, because the perl
package can be installed on any weird operating system.  Therefore,
you may need to specify the lexicon directory or alternative directories
explicitly.  However, you may also choose to install the lexicon files
inbetween the perl modules.

=section merge lexicon files with perl modules
By default, the filename which contains the package which contains the
textdomain's translator configuration is taken (that can be only one)
and changed into a directory name.  The path is then extended with C<messages>
to form the root of the lexicon: the top of the index.  After this,
the locale indication, the lc-category (usually LC_MESSAGES), and
the C<textdomain> followed by C<.po> are added.  This is exactly as
C<gettext(1)> does, but then using the PO text file instead of the MO
binary file.

=example lexicon in module tree
My module is named C<Some::Module> and installed in
some of perl's directories, say C<~perl5.8.8>.  The module is defining
textdomain C<my-domain>.  The translation is made into C<nl-NL.utf-8>
(locale for Dutch spoken in The Netherlands, utf-8 encoded text file).

The default location for the translation table is under
 ~perl5.8.8/Some/Module/messages/

for instance
 ~perl5.8.8/Some/Module/messages/nl-NL.utf-8/LC_MESSAGES/my-domain.po

There are alternatives, as described in M<Log::Report::Lexicon::Index>,
for instance
 ~perl5.8.8/Some/Module/messages/my-domain/nl-NL.utf-8.po
 ~perl5.8.8/Some/Module/messages/my-domain/nl.po

=section Locale search

The exact gettext defined format of the locale is
  language[_territory[.codeset]][@modifier]
The modifier will be used in above directory search, but only if provided
explicitly.

The manual C<info gettext> determines the rules.  During the search,
components of the locale get stripped, in the following order:
=over 4
=item 1. codeset
=item 2. normalized codeset
=item 3. territory
=item 4. modifier
=back

The normalized codeset (character-set name) is derived by
=over 4
=item 1. Remove all characters beside numbers and letters.
=item 2. Fold letters to lowercase.
=item 3. If the same only contains digits prepend the string "iso".
=back

To speed-up the search for the right table, the full directory tree
will be indexed only once when needed the first time.  The content of
all defined lexicon directories will get merged into one tree.

=section Example

My module is named C<Some::Module> and installed in some of perl's
directories, say C<~perl5>.  The module is defining textdomain
C<my-domain>.  The translation is made into C<nl-NL.utf-8> (locale for
Dutch spoken in The Netherlands, utf-8 encoded text file).

The translation table is taken from the first existing of these files:
  nl-NL.utf-8/LC_MESSAGES/my-domain.po
  nl-NL.utf-8/LC_MESSAGES/my-domain.po
  nl-NL.utf8/LC_MESSAGES/my-domain.po
  nl-NL/LC_MESSAGES/my-domain.po
  nl/LC_MESSAGES/my-domain.po

Then, attempts are made which are not compatible with gettext.  The
advantange is that the directory structure is much simpler.  The idea
is that each domain has its own locale installation directory, instead
of everything merged in one place, what gettext presumes.

In order of attempts:
  nl-NL.utf-8/my-domain.po
  nl-NL.utf8/my-domain.po
  nl-NL/my-domain.po
  nl/my-domain.po
  my-domain/nl-NL.utf8.po
  my-domain/nl-NL.po
  my-domain/nl.po

Filenames may get mutulated by the platform (which we will try to hide
from you [please help improve this]), and are treated case-INsensitive!
=cut

1;
