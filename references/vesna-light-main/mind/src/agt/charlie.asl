{ include( "vesna.asl" ) }
{ include( "playgrounds/office.asl" ) }

+!start
    :   .my_name( Me )
    <-  +ntpp( Me, reception );
        +my_desk( junior_11_desk );
        .wait( 2000 );
        !grab( cup2 );
        !go_to( coffee_machine );
        !take_coffee( cup2 );
        !go_to_work;
        !release( cup2 ).