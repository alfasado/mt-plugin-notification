package Notification::Plugin;
use strict;

sub _init_app {
    my $app = MT->instance;
    my $plugin = MT->component( 'Notification' );
    if ( my $objs = $app->config( 'NotificationObjectClasses' ) ) {
        my @objects = split( /,/, $objs );
        for my $obj ( @objects ) {
            MT->add_callback( 'cms_post_save.' . $obj, 9, $plugin, \&_post_save_object );
            my $model = MT->model( $obj );
            my $datasource = $model->datasource;
            if ( $datasource eq 'entry' ) {
                MT->add_callback( 'scheduled_post_published', 9, $plugin, \&_post_save_object );
                # PowerRevision
                MT->add_callback( 'cms_post_recover_from_revision.' . $obj, 9, $plugin, \&_post_save_object );
            } elsif ( ( $datasource eq 'customobject' ) || ( $datasource eq 'co' ) ||
                ( $datasource eq 'campaign' ) ) {
                # CustomObject.pack / Campaign
                MT->add_callback( 'post_publish.' . $obj , 9, $plugin, \&_post_save_object );
            }
        }
    }
    $app;
}

sub _post_save_object {
    my ( $cb, $app, $obj, $original ) = @_;
    my $plugin = MT->component( 'Notification' );
    if (! $obj->has_column( 'status' ) ) {
        return 1;
    }
    if ( $obj->has_column( 'status' ) != 2 ) {
        return 1;
    }
    my $objs = $app->config( 'NotificationObjectClasses' );
    my @objects = split( /,/, $objs );
    my $class = $obj->class;
    if (! grep( /^$class$/, @objects ) ) {
        return 1;
    }
    if ( $app->config( 'NotificationAtStatusCanged' ) ) {
        if ( defined $original ) {
            if ( $original->status == $obj->status ) {
                return 1;
            }
        }
    }
    my $body_field = $app->config( 'NotificationBodyBasename' );
    my $mail_field = $app->config( 'NotificationEmailBasename' );
    my $delimiter = $app->config( 'NotificationEmailDelimiter' );
    $body_field =~ s/^{{classname}}/$class/;
    $body_field = 'field.' . $body_field;
    $mail_field =~ s/^{{classname}}/$class/;
    $mail_field = 'field.' . $mail_field;
    if ( (! $obj->has_column( $body_field ) )
            || (! $obj->has_column( $mail_field ) ) ) {
        return 1;
    }
    my $body = $obj->$body_field;
    my $email = $obj->$mail_field;
    if (! $body || ! $email ) {
        return 1;
    }
    if ( $delimiter eq 'EOF' ) {
        $email =~ s/\r\n?/\n/g;
        my @addresses = split( /\n/, $email );
        my @emails;
        for my $address ( @addresses ) {
            push( @emails, $address ) if $address;
        }
        $email = join( ',', @emails );
        return 1 unless $email;
    }
    my $blog = $obj->blog;
    my $user = $obj->author;
    if ( ( ref $app ) =~ /^MT::App::/ ) {
        $user = $app->user;
    }
    my $param = {};
    $param->{ blog_id } = $blog->id;
    $param->{ blog_name } = $blog->name;
    $param->{ author_name } = $user->name;
    $param->{ author_nickname } = $user->nickname;
    $param->{ author_email } = $user->email;
    $param->{ body } = $body;
    $param->{ class_label } = $app->translate( $obj->class_label );
    if ( $obj->has_column( 'title' ) ) {
        $param->{ object_title } = $obj->title;
    } elsif( $obj->has_column( 'name' ) ) {
        $param->{ object_title } = $obj->name;
    } elsif( $obj->has_column( 'label' ) ) {
        $param->{ object_title } = $obj->label;
    }
    my $datasource = $obj->datasource;
    if ( ( $datasource eq 'entry' ) ||
        ( $datasource eq 'customobject' ) || ( $datasource eq 'co' ) ) {
        $param->{ permalink } = $obj->permalink;
    }
    my $columns = $obj->column_names;
    for my $col ( @$columns ) {
        $param->{ $col } = $obj->$col;
    }
    my $cgi = MT->config( 'CGIPath' );
    my $admin_script = MT->config( 'AdminScript' );
    my $query_str = $app->uri_params( mode => 'view',
                    args => { _type => $class,
                              blog_id => $blog->id,
                              id => $obj->id } );
    $param->{ script_uri } = $cgi;
    $param->{ edit_screen } = $cgi . $admin_script . $query_str;
    my $subject = $plugin->get_config_value( 'notification_mail_subject' );
    my $body = $plugin->get_config_value( 'notification_mail_body' );
    $subject = "<__trans_section component='Notification'>${subject}</__trans_section>";
    $body = "<__trans_section component='Notification'>${body}</__trans_section>";
    my $tmpl = MT->model( 'template' )->new;
    $tmpl->text( $subject );
    $subject = $app->build_page( $tmpl, $param );
    $tmpl = MT->model( 'template' )->new;
    $tmpl->text( $body );
    $body = $app->build_page( $tmpl, $param );
    require MT::Mail;
    my $from = $app->config( 'NotificationEmailFrom' );
    if ( $from && ( $from eq 'Author' ) ) {
        $from = $user->email;
    }
    my %head = ( To => $email, Subject => $subject );
    if ( $from ) {
        $head{ From } = $from;
    }
    MT::Mail->send( \%head, $body ) or die MT::Mail->errstr;
    return 1;
}

1;