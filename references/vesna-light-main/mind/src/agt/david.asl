{ include( "vesna.asl" ) }
{ include( "playgrounds/office.asl" ) }

+!start
    :   .my_name( Me )
    <-  +ntpp( Me, reception );
        +my_desk( junior_2_desk );
        .wait( 2000 );
        !grab( cup3 );
        !go_to( coffee_machine );
        !take_coffee( cup3 );
        !go_to_work;
        !release( cup3 ).