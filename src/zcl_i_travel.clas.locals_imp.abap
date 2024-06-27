CLASS lsc_z_i_travel DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.

    METHODS adjust_numbers REDEFINITION.


ENDCLASS.

CLASS lsc_z_i_travel IMPLEMENTATION.

  METHOD adjust_numbers.
    SELECT MAX( travel_id ) FROM /dmo/travel INTO @DATA(lv_max).

    LOOP AT mapped-z_i_travel ASSIGNING FIELD-SYMBOL(<ls_travel>).
      lv_max = lv_max + 1.
      <ls_travel>-travelid = lv_max.
    ENDLOOP.

    DATA(lv_booking_index) = 1.
    LOOP AT mapped-z_i_booking ASSIGNING FIELD-SYMBOL(<ls_booking>).
      DATA(ls_travel) = VALUE #( mapped-z_i_travel[ 1 ] OPTIONAL ).

      IF ls_travel IS INITIAL.
        SELECT MAX( booking_id ) FROM /dmo/booking WHERE travel_id = @<ls_booking>-%tmp-travelid INTO @DATA(lv_max_b).
        lv_max_b = lv_max_b + lv_booking_index.
        <ls_booking>-bookingid = lv_max_b.
      ELSE.
        <ls_booking>-bookingid = lv_booking_index.
      ENDIF.
      <ls_booking>-travelid = <ls_booking>-%tmp-travelid.
      lv_booking_index += lv_booking_index.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

CLASS lhc_z_i_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR z_i_travel RESULT result.
    METHODS setdefaultbegindate FOR DETERMINE ON MODIFY
      IMPORTING keys FOR z_i_travel~setdefaultbegindate.
    METHODS checkcurrency FOR VALIDATE ON SAVE
      IMPORTING keys FOR z_i_travel~checkcurrency.
    METHODS canceltravel FOR MODIFY
      IMPORTING keys FOR ACTION z_i_travel~canceltravel.
    METHODS counttravel FOR READ
      IMPORTING keys FOR FUNCTION z_i_travel~counttravel RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR z_i_travel RESULT result.

ENDCLASS.

CLASS lhc_z_i_travel IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD setdefaultbegindate.
    READ ENTITIES OF z_i_travel
      IN LOCAL MODE
      ENTITY z_i_travel
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_read_results)
      FAILED DATA(lt_failed)
      .

    MODIFY ENTITIES OF z_i_travel
      IN LOCAL MODE
      ENTITY z_i_travel
      UPDATE FIELDS ( begindate ) WITH VALUE #( FOR result IN lt_read_results (
        %tky = result-%tky
        begindate = COND #(
          WHEN result-begindate IS INITIAL THEN sy-datum
          ELSE result-begindate
        )
      )
      )
      REPORTED DATA(lt_reported_from_update)
      FAILED DATA(lt_failed_from_update)
      MAPPED DATA(lt_mapped_from_update).

    reported = CORRESPONDING #( DEEP lt_reported_from_update ).

  ENDMETHOD.

  METHOD checkcurrency.
    READ ENTITIES OF z_i_travel
     IN LOCAL MODE
     ENTITY z_i_travel
     ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_read_results)
     FAILED DATA(lt_failed_results).

    LOOP AT lt_read_results ASSIGNING
    FIELD-SYMBOL(<ls_result>).
      IF <ls_result>-currencycode <> 'EUR'.
        INSERT VALUE #(
           %pid = <ls_result>-%pid
           travelid = <ls_result>-travelid
        ) INTO TABLE failed-z_i_travel.

        INSERT VALUE #(
           %pid = <ls_result>-%pid
           travelid = <ls_result>-travelid
           %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Es wird nur Euro als Währung akzeptiert'
           )
           %element-currencycode = if_abap_behv=>mk-on
        ) INTO TABLE reported-z_i_travel.

      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD canceltravel.
    LOOP AT keys INTO DATA(ls_keys).
      SELECT * FROM /dmo/travel WHERE customer_id = @ls_keys-%param-customerid INTO TABLE @DATA(lt_travels).
      IF sy-subrc = 0.
        LOOP AT lt_travels INTO DATA(ls_travel).
          UPDATE /dmo/travel SET status = 'X' WHERE travel_id = @ls_travel-travel_id.
          IF sy-subrc = 0.
            APPEND VALUE #( travelid = ls_travel-travel_id %cid = ls_keys-%cid ) TO mapped-z_i_travel.
            APPEND VALUE #( travelid = ls_travel-travel_id %cid = ls_keys-%cid
                            %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                          text = 'Reise' && | | && ls_travel-travel_id && | | && 'erfolgreich aktualisiert' ) ) TO reported-z_i_travel.
          ELSE.
            APPEND VALUE #( travelid = ls_travel-travel_id %cid = ls_keys-%cid ) TO failed-z_i_travel.
            APPEND VALUE #( travelid = ls_travel-travel_id %cid = ls_keys-%cid
                            %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                          text = 'Fehler bei Reise ' && | | && ls_travel-travel_id ) ) TO reported-z_i_travel.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD counttravel.
    READ ENTITIES OF z_i_travel
     IN LOCAL MODE
     ENTITY z_i_travel
     ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_read_results)
     FAILED DATA(lt_failed_results).

    LOOP AT lt_read_results INTO DATA(ls_result).
      SELECT COUNT(*) FROM z_i_travel WHERE customerid = @ls_result-customerid INTO @DATA(lv_travels).
      IF sy-subrc = 0.
        APPEND VALUE #( travelid = ls_result-travelid %pid = ls_result-%pid ) TO result.
        APPEND VALUE #( travelid = ls_result-travelid %pid = ls_result-%pid
                       %msg = new_message_with_text( severity = if_abap_behv_message=>severity-information
                                                         text = |Der Kunde | && ls_result-customerid && | hat | && lv_travels && | Reisen| ) ) TO reported-z_i_travel.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD get_instance_features.
    SELECT *
      FROM z_i_travel
      FOR ALL ENTRIES IN @keys
      WHERE travelid = @keys-travelid
      INTO TABLE @DATA(lt_travels).

    result = VALUE #( FOR ls_travel IN lt_travels (
      travelid = ls_travel-travelid
      %features = SWITCH #( ls_travel-status
        WHEN 'N'
          THEN VALUE #(
            %delete = if_abap_behv=>fc-o-disabled
            %update = if_abap_behv=>fc-o-disabled
          )
        ELSE
          VALUE #(
            %delete = if_abap_behv=>fc-o-enabled
            %update = if_abap_behv=>fc-o-enabled
          )
      )
    ) ).

  ENDMETHOD.

ENDCLASS.
