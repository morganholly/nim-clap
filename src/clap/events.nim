import shared

type
    ClapEventFlag* {.size:sizeof(uint32).} = enum
        ceIS_LIVE,
        ceDONT_RECORD
    ClapEventFlags* = distinct uint32

    # clap_transport_flags; ord == bit position in the raw flags word
    ClapTransportFlag* {.size:sizeof(uint32).} = enum
        ctHAS_TEMPO             # 1 << 0
        ctHAS_BEATS_TIMELINE    # 1 << 1
        ctHAS_SECONDS_TIMELINE  # 1 << 2
        ctHAS_TIME_SIGNATURE    # 1 << 3
        ctIS_PLAYING            # 1 << 4
        ctIS_RECORDING          # 1 << 5
        ctIS_LOOP_ACTIVE        # 1 << 6
        ctIS_WITHIN_PRE_ROLL    # 1 << 7
    ClapTransportFlags* = distinct uint32

converter conv_clap_event_flags*(flags: set[ClapEventFlag]): ClapEventFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (1'u32 shl ord(f))
    return ClapEventFlags(res)

converter conv_clap_transport_flags*(flags: set[ClapTransportFlag]): ClapTransportFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (1'u32 shl ord(f))
    return ClapTransportFlags(res)

const
    # clap/fixedpoint.h: beat/second times are fixed-point; divide by 2^31 to get units
    CLAP_BEATTIME_FACTOR* = 1'i64 shl 31
    CLAP_SECTIME_FACTOR*  = 1'i64 shl 31

type
    ClapEventHeader* = object
        size       *: uint32         # event size including this header, eg: sizeof (clap_event_note)
        time       *: uint32         # sample offset within the buffer for this event
        space_id   *: uint16         # event space, see clap_host_event_registry
        event_type *: ClapEventType  # event type, originally named `type`
        flags      *: ClapEventFlags

    ClapEventType* {.size:sizeof(uint16).} = enum
        cetNOTE_ON             = 0,  #
        cetNOTE_OFF            = 1,  #
        cetNOTE_CHOKE          = 2,  #
        cetNOTE_END            = 3,  #
        cetNOTE_EXPRESSION     = 4,  # Represents a note expression; Uses clap_event_note_expression.
        cetPARAM_VALUE         = 5,  # PARAM_VALUE sets the parameter's value; uses clap_event_param_value.
        cetPARAM_MOD           = 6,  # PARAM_MOD sets the parameter's modulation amount; uses clap_event_param_mod.
        cetPARAM_GESTURE_BEGIN = 7,  # Indicates that the user started or finished adjusting a knob.
        cetPARAM_GESTURE_END   = 8,  #
        cetTRANSPORT           = 9,  # update the transport info; clap_event_transport
        cetMIDI                = 10, # raw midi event; clap_event_midi
        cetMIDI_SYSEX          = 11, # raw midi sysex event; clap_event_midi_sysex
        cetMIDI2               = 12  # raw midi 2 event; clap_event_midi2

    # wildcard, -1, means apply to all notes matching the other parts
    ClapEventNote* = object
        header     *: ClapEventHeader
        note_id    *: int32   # host provided note id >= 0, or -1 if unspecified or wildcard
        port_index *: int16   # port index from ext/note-ports; -1 for wildcard
        channel    *: int16   # 0..15, same as MIDI1 Channel Number, -1 for wildcard
        key        *: int16   # 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
        velocity   *: float64 # 0..1

    ClapNoteExpressionType* {.size:sizeof(int32).} = enum
        cneVOLUME     = 0, # with 0 < x <= 4, plain = 20 * log(x)
        cnePAN        = 1, # pan, 0 left, 0.5 center, 1 right

        # Relative tuning in semitones, from -120 to +120.
        # Semitones are in equal temperament and are doubles;
        # the resulting note would be retuned by `100 * evt->value` cents.
        cneTUNING     = 2,

        cneVIBRATO    = 3, # 0..1
        cneEXPRESSION = 4, # 0..1
        cneBRIGHTNESS = 5, # 0..1
        cnePRESSURE   = 6, # 0..1

    ClapNoteExpression* = distinct int32

    # wildcard, -1, means apply to all notes matching the other parts
    ClapEventNoteExpression* = object
        header     *: ClapEventHeader
        note_id    *: int32   # host provided note id >= 0, or -1 if unspecified or wildcard
        port_index *: int16   # port index from ext/note-ports; -1 for wildcard
        channel    *: int16   # 0..15, same as MIDI1 Channel Number, -1 for wildcard
        key        *: int16   # 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
        value      *: float64 # 0..1

    # wildcard, -1, means apply to all notes matching the other parts
    ClapEventParamMod* = ClapEventParamValue # combines identical _value and _mod types,
    ClapEventParamValue* = object            # which only differ in the name of one variable
        header     *: ClapEventHeader
        param_id   *: ClapID
        cookie     *: pointer
        note_id    *: int32   # host provided note id >= 0, or -1 if unspecified or wildcard
        port_index *: int16   # port index from ext/note-ports; -1 for wildcard
        channel    *: int16   # 0..15, same as MIDI1 Channel Number, -1 for wildcard
        key        *: int16   # 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
        val_amt    *: float64 # 0..1

    ClapEventParamGesture* = object
        header   *: ClapEventHeader
        param_id *: ClapID

    ClapEventTransport* = object
        # mirror of clap_event_transport; fields in exact C order.
        # beats/seconds fields are fixed-point: divide by 2^31 (see CLAP_*TIME_FACTOR).
        header             *: ClapEventHeader
        flags              *: ClapTransportFlags
        song_pos_beats     *: int64   # clap_beattime
        song_pos_seconds   *: int64   # clap_sectime
        tempo              *: float64  # bpm
        tempo_inc          *: float64  # tempo increment until next time-info event
        loop_start_beats   *: int64
        loop_end_beats     *: int64
        loop_start_seconds *: int64
        loop_end_seconds   *: int64
        bar_start          *: int64
        bar_number         *: int32   # bar at song pos 0 has number 0
        tsig_num           *: uint16
        tsig_denom         *: uint16

    ClapEventMidi* = object
        header     *: ClapEventHeader
        port_index *: uint16
        data       *: array[3, uint8]

    ClapEventMidiSysex* = object
        header     *: ClapEventHeader
        port_index *: uint16
        buffer     *: ptr UncheckedArray[uint8]
        size       *: uint32

    ClapEventMidi2* = object
        header     *: ClapEventHeader
        port_index *: uint16
        data       *: array[4, uint32]

    ClapEventUnion* {.union.} = object
        # contains header in all
        kindNote         *: ClapEventNote
        kindNoteExpr     *: ClapEventNoteExpression
        kindParamValMod  *: ClapEventParamValue
        kindParamGesture *: ClapEventParamGesture
        kindTransport    *: ClapEventTransport
        kindMidi         *: ClapEventMidi
        kindMidiSysex    *: ClapEventMidiSysex
        kindMidi2        *: ClapEventMidi2

    ClapInputEvents* = object
        ctx *: pointer
        size *: proc (list: ptr ClapInputEvents): uint32 {.cdecl.}
        get *: proc (list: ptr ClapInputEvents, index: uint32): ptr ClapEventUnion {.cdecl.}

    ClapOutputEvents* = object
        ctx *: pointer
        try_push *: proc (list: ptr ClapOutputEvents, event: ptr ClapEventUnion): bool {.cdecl.}