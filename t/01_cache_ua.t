use Test::More qw/no_plan/;
use Egg::Helper::VirtualTest;

my $v= Egg::Helper::VirtualTest->new;
   $v->prepare(
     controller=> { egg_includes=> [qw/Cache::UA/] },
     create_files=> [$v->yaml_load( join '', <DATA> )],
     config=> {
       plugin_cache_ua => {
         cache_name => 'FileCache',
         allow_hosts=> [qw/127.0.0.1/],
         },
       },
     );

ok my $e= $v->egg_pcomp_context;
isa_ok $e, 'Egg::Plugin::Cache::UA';
isa_ok $e, 'Egg::Plugin::LWP';
isa_ok $e, 'Egg::Plugin::Cache';
can_ok $e, 'cache_ua';
can_ok $e, 'ua';
can_ok $e, 'cache';
ok my $ca= $e->cache_ua;
isa_ok $ca, 'Egg::Plugin::Cache::UA::handler';
can_ok $ca, qw/get output delete remove cache __get_args/;


__DATA__
filename: lib/<$e.project_name>/Cache/FileCache.pm
value: |
 package <$e.project_name>::Cache::FileCache;
 use strict;
 use warnings;
 
 __PACKAGE__->include('Cache::FileCache');
 
 __PACKAGE__->config(
   namespace  => 'TestTest',
   cache_root => '\<$e.dir.cache>',
   );
 
 1;
