#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature qw/say/;
#use Smart::Comments;
#use Data::Printer;
use Net::Twitter::Lite::WithAPIv1_1;
use Config::Pit;
use Time::Piece;
use Time::Seconds;
use IO::All -utf8;
use LWP::Simple qw/mirror get/;
use XML::FeedPP;
use Text::Truncate;
use Encode qw/decode_utf8 encode_utf8/;
use JSON;
use URI::Escape::XS qw/uri_escape/;
use open qw/:utf8 :std/;


my $MENU_DIR            = './menu/';
my $CACHE_DIR           = './cache/';
my $HANKAKU_SPACE       = q{ };
my $FEED_URL            = 'http://www.jaist.ac.jp/cafe/feed/';
my $FEED_FIRST_ITEM_NUM = 0;
my $NUM_MENU_COLUMN     = 9;
my $LUNCH_END_HOUR      = 14;
my $DINNER_END_HOUR     = 20;
my $TWEET_MAX_STRLEN    = 140;
my $BITLY_BASE_URL      = 'http://api.bit.ly/v3/shorten';

my $config = pit_get('JAIST_GOHAN', require => {
    'consumer_key'        => 'Input consumer_key',
    'consumer_secret'     => 'Input consumer_secret',
    'access_token'        => 'Input access_token',
    'access_token_secret' => 'Input access_token_secret',
    'bitly_user'          => 'Input bitly_user',
    'bitly_key'           => 'Input bitly_key',
});

my $twit = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key        => $config->{consumer_key},
    consumer_secret     => $config->{consumer_secret},
    access_token        => $config->{access_token},
    access_token_secret => $config->{access_token_secret},
    ssl                 => 1,
);


my $t    = localtime;
my $hour = $t->hour;

if ($t->hour < $DINNER_END_HOUR)
{
    my $today      = $t->ymd;
    my $menu_today = fetch_menu($today, $hour);

    tweet($menu_today) if defined $menu_today;
}
else
{
    $t += ONE_DAY;
    my $tomorrow      = $t->ymd;
    my $menu_tomorrow = fetch_menu($tomorrow, 0);

    tweet($menu_tomorrow) if defined $menu_tomorrow;
}

warn 'フィードのチェックに失敗しました' if check_feed() == -1;
follow_and_remove(); # 自動相互フォロー

exit;




sub fetch_menu
{
    my ($ymd, $hour) = @_;

    ### $ymd

    my ($year, $month, $mday) = split(/-/, $ymd);
    $mday =~ s/0([0-9])/$1/;

    my $menu_file = "${MENU_DIR}${year}/${month}.txt";
    return unless -f $menu_file;

    my $content = io($menu_file)->slurp;
    $content =~ s/\n\n+/\n/g;
    $content =~ s/\n[^0-9]//g;

    my @lines = split(/\n/, $content);

    for my $line (@lines)
    {
        my @items = split(/$HANKAKU_SPACE/o, $line);

        next if $items[0] ne $mday;
        return "${month}月${mday}日の食堂は休みです。\n" if scalar @items < 3;

        my (
            $mday,    $wday,    $lunchA,       $lunchB,        $lunchC,
            $dinnerA, $dinnerB, $higawari_men, $original_plate
        )
        = map { length $_ ? $_ : 'なし' } @items[0 .. ($NUM_MENU_COLUMN - 1)];

        $month =~ s/0([0-9])/$1/;

        my $menu = "${month}月${mday}日（${wday}）のメニュー▼\n";

        if ($hour < $LUNCH_END_HOUR)
        {
            $menu .= <<"EOS";
　ランチＡ：$lunchA
　ランチＢ：$lunchB
　ランチＣ：$lunchC
EOS
        }

        $menu .= <<"EOS";
ディナーＡ：$dinnerA
ディナーＢ：$dinnerB
日替わり麺：$higawari_men
オリジナル：$original_plate
EOS

        return $menu;
    }

    return 'なんかえらー';
}


sub check_feed
{
    my $cache = "${CACHE_DIR}feed.xml";

    my $cache_last_update = (stat($cache))[9] // 0;

    # もし新しければ上書きされる
    LWP::Simple::mirror($FEED_URL, $cache) or return -1;

    my $feed_last_update = (stat($cache))[9] // 0;

    ### $cache_last_update
    ### $feed_last_update

    if ($feed_last_update > $cache_last_update)
    {
        # フィードが更新されている
        my $feed = XML::FeedPP->new($cache);
        my $item = $feed->get_item($FEED_FIRST_ITEM_NUM); # 短時間（１日以内）に複数回更新されない想定なのに注意

        my $title = decode_utf8 $item->title;
        my $desc  = decode_utf8 $item->description;
        my $link  = decode_utf8 $item->link;

        if ($desc =~ /(http:[^\s]+\.pdf)/)
        {
            my $url = shorten_URL($1);
            $desc =~ s/http:[^\s]+\.pdf/$url/;
        }

        $link = shorten_URL($link);

        ### $title
        ### $desc
        ### $link

        my $feed_info = <<"EOS";
【JAIST Cafeteria】「${title}」${desc} $link
EOS

        ### $feed_info
        tweet($feed_info);
    }
}


sub tweet
{
    my ($text) = @_;

    $text = truncstr($text, $TWEET_MAX_STRLEN);

    $twit->update($text);
}


sub shorten_URL
{
    my $url      = uri_escape(shift);
    my $apiurl   = "${BITLY_BASE_URL}?login=%s&apiKey=%s&longUrl=%s&format=json";
    my $bitly    = sprintf($apiurl, $config->{bitly_user}, $config->{bitly_key}, $url);
    my $json     = LWP::Simple::get($bitly);
    my $res      = decode_json($json);
    my $shortURL = $res->{data}{url};

    return $shortURL;
}


sub follow_and_remove
{
    my $friends   = $twit->friends_ids;
    my $followers = $twit->followers_ids;

    my %ids = map +( $_ => 1 ), @{ $friends->{ids} }; # 差分を抽出

    for my $id (@{ $followers->{ids} })
    {
        my $result = delete $ids{$id};

        # 未フォローユーザをフォロー
        unless (defined $result)
        {
            eval { $twit->create_friend({ user_id => $id }) };
        }
    }

    # 残りはリムーブすべきユーザ
    for my $id (keys %ids)
    {
        eval { $twit->destroy_friend({ user_id => $id }) };
    }
}
