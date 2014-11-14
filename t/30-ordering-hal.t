#!/usr/bin/env perl

use lib "t/lib";
use TestKit;
use Sort::Key qw/multikeysorter/;

fixtures_ok qw/basic/;

sub is_ordered {
    my ($got, $value_sub, @types) = @_;

    my $sorter = multikeysorter($value_sub, @types);
    my @ordered = $sorter->(@$got);

    my @got_view = map { join "/", $value_sub->($_) } @$got;
    my @ord_view = map { join "/", $value_sub->($_) } @ordered;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    eq_or_diff_data \@got_view, \@ord_view, 'ordered';
}

sub hack_str {
    my $str = shift;
    # XXX the s/\./~/g is a hack to workaround an apparent difference between
    # perl's lexical sorting and postgres character sorting
    # eg they order 'danielle.carne' vs 'daniel.rabiner' and
    # 'salesman' vs 'sales team' differently. Unicode collation?
    $str =~ s/ /~/g;
    return lc $str;
}


subtest "===== Ordering =====" => sub {
    my ($self) = @_;

    my $app = WebAPI::DBIC::WebApp->new({
        schema => Schema,
    })->to_psgi_app;


    my $base = "/cd?rows=1000"; # rows count must include all rows in set for tests to pass
    my %cds;
    my @cds;

    test_psgi $app, sub {
        my $data = dsresp_ok(shift->(dsreq_hal( GET => "$base&order=me.cdid" )));
        my $set = has_hal_embedded_list($data, "cd", 2)
            or return;
        @cds = @$set;
        %cds = map { $_->{cdid} => $_ } @cds;
        is ref $cds{$_}, "HASH", "/cd includes $_"
            for (1..3);
        ok $cds{1}{title}, "/cd data looks sane";
    };

    test_psgi $app, sub {
        my $data = dsresp_ok(shift->(dsreq_hal( GET => "$base&order=me.cdid%20desc" )));
        my $set = has_hal_embedded_list($data, "cd", 2);
        is_deeply $set, [ reverse @cds], 'reversed';
        is_ordered($set, sub { $_->{cdid} }, '-int');
    };

    test_psgi $app, sub {
        my $data = dsresp_ok(shift->(dsreq_hal( GET => "$base&order=me.title%20desc,cdid%20desc" )));
        my $set = has_hal_embedded_list($data, "cd", 2);
        cmp_deeply $set, bag(@cds), 'same set of rows returned';
        ok not eq_deeply $set, \@cds, 'order has changed from original';
        # XXX the s/\./~/g is a hack to workaround an apparent difference between
        # perl's lexical sorting and postgres character sorting
        # eg they order danielle.carne and daniel.rabiner differently
        is_ordered($set, sub { return hack_str($_->{title}), $_->{cdid} }, '-str', '-int');
    };

    test_psgi $app, sub {
        my $data = dsresp_ok(shift->(dsreq_hal( GET => "$base&order=me.title,cdid%20asc" )));
        my $set = has_hal_embedded_list($data, "cd", 2);
        cmp_deeply $set, bag(@cds), 'same set of rows returned';
        ok not eq_deeply $set, \@cds, 'order has changed from original';
        is_ordered($set, sub { return hack_str($_->{title}), $_->{cdid} }, 'str', 'int');
    };

    note "===== Ordering with prefetch =====";

    test_psgi $app, sub {
        # the extra me.* param is to make this query be less expensive on our data set
        my $data = dsresp_ok(shift->(dsreq_hal( GET => "/cd?prefetch=artist&order=artist.name" )));
        my $set = has_hal_embedded_list($data, "cd", 2);
        is_ordered($set, sub { hack_str($_->{_embedded}{artist}{name}) }, 'str');
    };

    test_psgi $app, sub {
        # the extra me.* param is to make this query be less expensive
        my $data = dsresp_ok(shift->(dsreq_hal( GET => "/cd?prefetch=artist,genre&order=genre.name%20desc,artist.name%20asc" )));
        my $set = has_hal_embedded_list($data, "cd", 2);
        cmp_ok scalar @$set, '>=', 5, 'matched sufficient records';
        is_ordered($set, sub { lc $_->{_embedded}{genre}{name}, lc $_->{_embedded}{artist}{name} }, '-str', 'str');
    };
};

done_testing();
