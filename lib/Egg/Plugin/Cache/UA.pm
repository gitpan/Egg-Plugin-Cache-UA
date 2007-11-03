package Egg::Plugin::Cache::UA;
#
# Masatoshi Mizuno E<lt>lusheE<64>cpan.orgE<gt>
#
# $Id: UA.pm 191 2007-08-08 06:10:57Z lushe $
#
use strict;
use warnings;
use base qw/
  Egg::Plugin::Cache
  Egg::Plugin::LWP
  /;

our $VERSION = '0.02';

=head1 NAME

Egg::Plugin::Cache::UA - The result of LWP is cached for Egg::Plugin.

=head1 SYNOPSIS

  use Egg qw/Cache::UA/;
  .......
  .....
  
  __PACKAGE__->dispatch_map(
    cache=> {
      google => sub {
        my($e)= @_;
        $e->cache_ua->output('http://xxx.googlesyndication.com/pagead/show_ads.js');
        },
      brainer=> sub {
        my($e)= @_;
        $e->cache_ua->output('http://xxx.brainer.jp/ad.js');
        },
      },
    );

=head1 DESCRIPTION

This module cache and recycles the request result of Egg::Plugin::LWP.

Especially, I think that it is effective in an advertising usage of the contents
match system of the type that returns the JAVA script.

It becomes difficult to receive the influence of the response speed of advertisement
ASP server by the action of cashe.

Because this module has succeeded to Egg::Plugin::LWP and Egg::Plugin::Cache, 
it is not necessary to read separately.

=head1 CONFIGURATION

Please go in Configuration of this module with the key 'plugin_cache_ua'.

* It is necessary to setup L<Egg::Plugin::LWP> and L<Egg::Plugin::Cache>.

* Especially, the setting of User-Agent recommends the thing customized without
  fail in Egg::Plugin::LWP.

=head2 allow_hosts

Please set the host name that permits the use of cashe with ARRAY.

* It is necessary to set it.

  allow_hosts => [qw/ www.domain.com domain.com domain.net /],

* Because each value is put on 'quotemeta', the regular expression is not 
  effective well. Please enumerate the host name usually.

* Under the influences of the proxy and the security software, etc. though it
  checks with 'HTTP_REFERER' When it is not possible to acquire it, it is not
  refused because the thing that cannot be acquired can break out, too.

=head2 content_type

Default of sent contents type.

* Please set it if you call the output method.

'text/html' is used if it unsets it.

  content_type=> 'text/javascript',

=head2 content_type_error

Contents type for error screen when some errors occur.

Default is 'text/html';

=head2 cache_name

Cashe name set to Egg::Plugin::Cache.

There is no default and set it, please.

  cache_name => 'FileCache',

=head2 cache_expires

When L<Cache::Memcached > is used with Egg::Plugin::Cache, the validity term
of cashe is set by this setting.

* It is not necessary usually.

  cache_expires=> 60* 60,  # one hour.

=head2 expires or last_modified

The response header to press the cashe of the browser side is set.

* It specifies it by the form used by CGI module.

  expires       => '+1d',
  last_modified => '+1d',

=head1 METHODS

=head2 cache_ua

The Egg::Plugin::Cache::UA::handler object is returned.

  my $cache_ua= $e->cache_ua;

=head1 HADLER METHODS

It is a method of the object returned by $e-E<gt>cache_ua.

=head2 get ( [URL], [OPTION] )

The GET request is sent to URL.
* It is not possible to request it to URL that the methods other than GET are
  demanded.

The content is returned if becoming a hit to cashe.

The HASH reference returns to the return value without fail.

  my $res= $e->cache_ua->get('http://domainname/');
  
  if ($res->{is_success}) {
    $e->stash->{request_content}= \$res->{content};
  } else {
    $e->finished($res->{status} || 500);
  }

The content of HASH is as follows.

=over 4

=item * is_success

Succeeding in the request is true.

=item * status

There is a status line obtained because of the response.

=item * content_type

There is a contents type obtained because of the response.

* Instead, the default of the setting enters when the contents type is not obtained.

=item * content

There is a content of contents obtained because of the response.

=item * error

One the respondent error message enters when is_success is false.

=item * no_hit

When not becoming a hit to cashe, it becomes true.

=back

=head2 output ( [URL], [OPTION] )

L<Egg::Response> is set directly based on information obtained by the get method.

The response header set here is as follows.

=over 4

=item * X-CACHE-UA

When no_hit is only false, it is set.
It will be said that it became a hit to cashe in a word.

=item * expires or last_modified

It is set based on the setting.

=item * status

If the status line is obtained, it is set.

=item * content_type

The obtained contents type is set.

=back

The content of content is set in $e-E<gt>response-E<gt>body.
When content is not obtained by the error's occurring by the request, the content
of error is set.

* Because $e-E<gt>response-E<gt>body is defined, the processing of view comes to
  be passed by the operation of Egg.

=head2 delete ( [URL] )

The data of URL is deleted from cashe.

  $e->delete('http://domainname/');

=over 4

=item * Alias is 'remove'.

=back

=head2 cache

The cashe object set to 'cache_name' is returned.

  my $cache= $e->cache_ua->cache;

=cut

sub _setup {
	my($e)= @_;
	my $conf= $e->config->{plugin_cache_ua} ||= {};
	$conf->{content_type}       ||= 'text/html';
	$conf->{content_type_error} ||= 'text/html';
	$conf->{cache_name}    || die q{ I want setup 'cache_name'. };
	$conf->{cache_expires} ||= undef;
	my $allows= $conf->{allow_hosts} || die q{ I want setup 'allow_hosts' };
	my $regex = join '|',
	   map{quotemeta}(ref($allows) eq 'ARRAY' ? @$allows: $allows);

	no warnings 'redefine';
	*Egg::Plugin::Cache::UA::handler::referer_check= sub {
		my($self)= @_;
		my $referer= $self->e->request->referer || return 1;
		$referer=~m{^https?\://(?:$regex)} ? 1: 0;
	  };

	$e->next::method;
}
sub cache_ua {
	$_[0]->{cache_ua} ||= Egg::Plugin::Cache::UA::handler->new
	                       ($_[0], $_[0]->config->{plugin_cache_ua});
}

package Egg::Plugin::Cache::UA::handler;
use strict;
use warnings;
use Carp qw/croak/;
use base qw/Egg::Base/;

sub get {
	my($self, $url, $option)= __get_args(@_);
	$self->referer_check || return 0;
	my $result= $self->cache->get($url) || do {
		my %attr;
		if (my $res= $self->e->ua->request( GET => $url )) {
			if ($res->is_success) {
				$attr{is_success}= 1;
				if (my $status= $res->status_line) {
					$attr{status}= $status if $status!~/^200/;
				}
				my @content_type= $res->header('content_type') || "";
				$attr{content_type}= $content_type[0]
				                  || $option->{content_type};
				$attr{content}= $res->content || "";
			} else {
				$attr{status}= $res->status_line || '403 Forbidden';
				$attr{error} = " Error in $url : ". $res->status_line;
			}
		} else {
			$attr{status}= "408 Request Time-out";
			$attr{error} = " $url doesn't return the response. ";
		}
		$attr{content_type} ||= $option->{content_type_error};
		$attr{content}      ||= "";
		$self->cache->set($url, \%attr, $option->{cache_expires});
		$attr{no_hit}= 1;
		\%attr;
	  };
}
sub output {
	my($self, $url, $option)= __get_args(@_);
	my $cache= $self->get($url, $option) || {
	  no_hit       => 1,
	  status       => '500 Internal Server Error',
	  content_type => $option->{content_type_error},
	  error        => ' referer is illegal.',
	  };
	my $response= $self->e->response;
	$response->headers->header('X-CACHE-UA'=> 'hit')
	         unless $cache->{no_hit};
	$response->is_expires($option->{expires})
	         if $option->{expires};
	$response->last_modified($option->{last_modified})
	         if $option->{last_modified};
	$response->status($cache->{status}) if $cache->{status};
	$response->content_type($cache->{content_type});
	$cache->{content}= $cache->{error} if $cache->{error};
	$response->body(\$cache->{content});
}
sub delete {
	my $self= shift;
	my $url = shift || croak q{ I want url. };
	$self->cache->remove($url);
}
*remove= \&delete;

sub cache {
	$_[0]->{cache} ||= do {
		my $name= $_[0]->param('cache_name');
		$_[0]->e->cache($name) || die qq{ '$name' cache is not found. };
	  };
}
sub __get_args {
	my $self  = shift;
	my $url   = shift || croak q{ I want URL. };
	my %option= (
	  %{$self->params},
	  %{ $_[1] ? {@_}: ($_[0] || {}) },
	  );
	($self, $url, \%option);
}

=head1 SEE ALSO

L<Egg::Plugin::LWP>,
L<Egg::Plugin::Cache>,
L<Egg::Response>,
L<Egg::Release>,

=head1 AUTHOR

Masatoshi Mizuno E<lt>lusheE<64>cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 2007 by Bee Flag, Corp. E<lt>http://egg.bomcity.com/E<gt>, All Rights Reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut

1;
