library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bus_bridge_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 1;
        dev_mem_begin: integer := 0;
        dev_mem_end: integer := 0
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  system bus interface signals
        ext_bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        ext_bus_strobe_M: inout std_logic;
        ext_bus_strobe_S: inout std_logic;
        ext_bus_keep: inout std_logic;
        ext_bus_done_S: inout std_logic;
        ext_bus_rq: out std_logic;
        ext_bus_grant: in std_logic;
        ext_bus_busy: in std_logic;
        --  sub-system bus interface signals
        int_bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        int_bus_strobe_M: inout std_logic;
        int_bus_strobe_S: inout std_logic;
        int_bus_keep: inout std_logic;
        int_bus_done_S: inout std_logic;
        int_bus_rq_lines: in std_logic_vector(6 downto 0);
        int_bus_grant_lines: out std_logic_vector(6 downto 0);
        int_bus_busy: out std_logic;
        --  added lines for system bus pre-booking
        --  these pre-booking signals are driven by the 'subbus' module and are independent of the device interface itself (they exist only for sub-devices)
        int2ext_req: in std_logic_vector(6 downto 0);   --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        int2ext_rdy: out std_logic_vector(6 downto 0);  --  this line will go high if the system bus has been granted
        int2ext_err: out std_logic_vector(6 downto 0);  --  this will display an error in case something went wrong with the booking
        --  debug lines
        dbg_stage: out natural;
        dbg_stage_extbus: out natural;
        dbg_stage_intbus: out natural     
    );
end bus_bridge_v2;

architecture Behavioral of bus_bridge_v2 is
    --  external bus
    --  control signals
    signal r_ext_command_to: std_logic := '0';
    signal r_ext_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_ext_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_ext_latch: std_logic := '0';
    --signal r_ext_ack: std_logic := '0';
    signal r_ext_keep: std_logic := '0';
    signal r_ext_book: std_logic := '0';
    signal r_ext_clear: std_logic := '0';
    --  output signals
    signal s_ext_command_from: std_logic;
    signal s_ext_address_from: std_logic_vector(addr_width-1 downto 0);
    signal s_ext_data_from: std_logic_vector(data_width-1 downto 0);
    signal s_ext_done: std_logic;
    signal s_ext_drdy: std_logic;
    signal s_ext_booked: std_logic;
    signal s_ext_rq_error: std_logic;
    signal s_ext_mode: std_logic_vector(1 downto 0);
    --  sampling signals
    signal ss_ext_done: std_logic;
    signal ss_ext_drdy: std_logic;
    signal ss_ext_booked: std_logic;
    signal ss_ext_rq_error: std_logic;
    signal ss_ext_mode: std_logic_vector(1 downto 0);
    
    signal ss_ext_command_from: std_logic;
    signal ss_ext_address_from: std_logic_vector(addr_width-1 downto 0);
    signal ss_ext_data_from: std_logic_vector(data_width-1 downto 0);
    
    --  internal bus
    --  control signals
    signal r_int_command_to: std_logic := '0';
    signal r_int_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_int_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_int_latch: std_logic := '0';
    --signal r_int_ack: std_logic := '0';
    signal r_int_keep: std_logic := '0';
    signal r_int_book: std_logic := '0';
    signal r_int_clear: std_logic := '0';
    --  output signals
    signal s_int_command_from: std_logic;
    signal s_int_address_from: std_logic_vector(addr_width-1 downto 0);
    signal s_int_data_from: std_logic_vector(data_width-1 downto 0);
    signal s_int_done: std_logic;
    signal s_int_drdy: std_logic;
    signal s_int_booked: std_logic;
    signal s_int_rq_error: std_logic;
    signal s_int_mode: std_logic_vector(1 downto 0);
    --  sampling signals
    signal ss_int_done: std_logic;
    signal ss_int_drdy: std_logic;
    signal ss_int_booked: std_logic;
    signal ss_int_rq_error: std_logic;
    signal ss_int_mode: std_logic_vector(1 downto 0);
    signal ss_int_command_from: std_logic;
    signal ss_int_address_from: std_logic_vector(addr_width-1 downto 0);
    signal ss_int_data_from: std_logic_vector(data_width-1 downto 0);    
    
    --  internal bus arbiter signals
    signal s_int_rq_lines: std_logic_vector(7 downto 0);
    signal s_int_grant_lines: std_logic_vector(7 downto 0);
    signal s_int_busy: std_logic;
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_BOOK_TERM,
    s_EXT_BOOK_0, s_EXT_BOOK_1, s_EXT_BOOK_2, s_EXT_BOOK_3, s_EXT_BOOK_4, s_TRAP,
    s_INT_2_EXT_0, s_INT_2_EXT_1, s_INT_2_EXT_2, s_INT_2_EXT_3, s_INT_2_EXT_4,
    s_EXT_2_INT_0, s_EXT_2_INT_1, s_EXT_2_INT_2, s_EXT_2_INT_3, s_EXT_2_INT_4);
    signal r_stage: t_SM := s_INIT;
    
    --  booking stuff
    signal s_int2ext_req: std_logic_vector(6 downto 0);
    signal r_int2ext_rdy: std_logic_vector(6 downto 0) := (others=>'0');
    signal r_int2ext_err: std_logic_vector(6 downto 0) := (others=>'0');
    signal int2ext_flag: std_logic;
    signal ss_int2ext_flag: std_logic;
    
    --  debug
    signal r_dbg_stage: natural := 0;
    
    --  synchronizer
    signal ss_sync_0: std_logic := '0';
    signal ss_sync_1: std_logic := '0';
    
begin
    --  output drives
    int_bus_grant_lines <= s_int_grant_lines(7 downto 1);
    int2ext_rdy <= r_int2ext_rdy;
    int2ext_err <= r_int2ext_err;
    dbg_stage <= r_dbg_stage;
    
    --  assignments
    s_int_rq_lines(7 downto 1) <= int_bus_rq_lines;
    int_bus_busy <= s_int_busy;
    
    --  system bus interface
    EXTBUS_INT: entity work.bus_interface_v2(Behavioral)
                generic map (
                    dev_mem_begin => dev_mem_begin,
                    dev_mem_end => dev_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  bus lines and logic
                    bus_lines => ext_bus_lines,
                    bus_strobe_M => ext_bus_strobe_M,
                    bus_strobe_S => ext_bus_strobe_S,
                    bus_keep => ext_bus_keep,
                    bus_done_S => ext_bus_done_S,
                    --  bus arbiter
                    bus_rq => ext_bus_rq,
                    bus_grant => ext_bus_grant,
                    bus_busy => ext_bus_busy,
                    --  interface addr/data
                    command_to => r_ext_command_to,
                    command_from => s_ext_command_from,
                    address_to => r_ext_address_to,
                    address_from => s_ext_address_from,
                    data_to => r_ext_data_to,
                    data_from => s_ext_data_from,
                    --  interface sync
                    latch => r_ext_latch,
                    done => s_ext_done,
                    drdy => s_ext_drdy,
                    keep => r_ext_keep,
                    book => r_ext_book,
                    booked => s_ext_booked,
                    rq_error => s_ext_rq_error,
                    interface_mode => s_ext_mode,
                    clear => r_ext_clear,
                    --  debug
                    dbg_stage => dbg_stage_extbus
                );

    --  sub-bus arbiter
    INTBUS_ARB: entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => 8
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  request lines
                    rq_lines => s_int_rq_lines,
                    grant_lines => s_int_grant_lines,
                    busy => s_int_busy
                );
    
    --  sub-bus interface
    INTBUS_INT: entity work.bus_interface_v2(Behavioral)
                    generic map (
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  covering the entire 23 bit space so that every op
                        --  issued by the sub-devices towards the system bus will pass through here.
                        --  of course this means that inter-sub-dev communication is not allowed directly
                        --  since the whole system operation must always be synchronous.
                        dev_mem_begin => 0,
                        dev_mem_end => 8388607
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  bus lines and logic
                        bus_lines => int_bus_lines,
                        bus_strobe_M => int_bus_strobe_M,
                        bus_strobe_S => int_bus_strobe_S,
                        bus_keep => int_bus_keep,
                        bus_done_S => int_bus_done_S,
                        --  bus arbiter
                        bus_rq => s_int_rq_lines(0),
                        bus_grant => s_int_grant_lines(0),
                        bus_busy => s_int_busy,
                        --  interface addr/data
                        command_to => r_int_command_to,
                        command_from => s_int_command_from,
                        address_to => r_int_address_to,
                        address_from => s_int_address_from,
                        data_to => r_int_data_to,
                        data_from => s_int_data_from,
                        --  interface sync
                        latch => r_int_latch,
                        done => s_int_done,
                        drdy => s_int_drdy,
                        keep => r_int_keep,
                        book => r_int_book,
                        booked => s_int_booked,
                        rq_error => s_int_rq_error,
                        interface_mode => s_int_mode,
                        clear => r_int_clear,
                        --  debug
                        dbg_stage => dbg_stage_intbus
                    );
    
    --  int2ext
    int2ext_flag <= int2ext_req(0) or int2ext_req(1) or int2ext_req(2) or int2ext_req(3) or int2ext_req(4) or int2ext_req(5) or int2ext_req(6);
    
    --  SAMPLER process
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_int2ext_flag <= '0';
                                ss_ext_mode <= (others=>'0');
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s_IDLE =>
                                ss_int2ext_flag <= int2ext_flag;
                                ss_ext_mode <= s_ext_mode;
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s_BOOK_TERM =>
                                ss_int2ext_flag <= int2ext_flag;
                            
                            when s_EXT_BOOK_0 =>
                                ss_sync_0 <= '1';
                                ss_ext_booked <= s_ext_booked;
                                ss_ext_rq_error <= s_ext_rq_error;
                            
                            when s_EXT_BOOK_1 =>
                                ss_sync_0 <= '0';
                                ss_ext_rq_error <= s_ext_rq_error;
                            
                            when s_EXT_BOOK_2 =>
                                ss_sync_0 <= '0';
                                ss_ext_booked <= s_ext_booked;
                            
                            when s_EXT_BOOK_3 =>
                                ss_sync_0 <= '1';
                                s_int2ext_req <= int2ext_req;
                            
                            when s_EXT_BOOK_4 =>
                                ss_sync_0 <= '0';
                                s_int2ext_req <= int2ext_req;
                            
                            when s_INT_2_EXT_0 =>
                                ss_int_drdy <= s_int_drdy;
                                ss_int_command_from <= s_int_command_from;
                                ss_int_address_from <= s_int_address_from;
                                ss_int_data_from <= s_int_data_from;
                                ss_int_done <= s_int_done;    
                                ss_sync_0 <= '1';                            
                                                            
                            when s_INT_2_EXT_1 =>
                                ss_ext_drdy <= s_ext_drdy;
                                ss_ext_command_from <= s_ext_command_from;
                                ss_ext_address_from <= s_ext_address_from;
                                ss_ext_data_from <= s_ext_data_from;
                                ss_ext_done <= s_ext_done;
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '1';
                            
                            when s_INT_2_EXT_2 =>
                                ss_int_drdy <= s_int_drdy;
                                ss_sync_1 <= '0';
                            
                            when s_INT_2_EXT_3 =>
                                ss_ext_drdy <= s_ext_drdy;
                            
                            --  this was added in symmetry with s_EXT_2_INT_4
                            when s_INT_2_EXT_4 =>
                                ss_sync_0 <= '1';
                                ss_int_mode <= s_int_mode;
                                ss_int2ext_flag <= int2ext_flag;
                            
                            when s_EXT_2_INT_0 =>
                                ss_ext_drdy <= s_ext_drdy;
                                ss_ext_command_from <= s_ext_command_from;
                                ss_ext_address_from <= s_ext_address_from;
                                ss_ext_data_from <= s_ext_data_from;
                                ss_ext_done <= s_ext_done;
                                ss_sync_0 <= '1';
                            
                            when s_EXT_2_INT_1 =>
                                ss_int_drdy <= s_int_drdy;
                                ss_int_command_from <= s_int_command_from;
                                ss_int_address_from <= s_int_address_from;
                                ss_int_data_from <= s_int_data_from;
                                ss_int_done <= s_int_done;
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '1';
                            
                            when s_EXT_2_INT_2 =>
                                ss_ext_drdy <= s_ext_drdy;
                                ss_sync_1 <= '0';
                            
                            when s_EXT_2_INT_3 =>
                                ss_int_drdy <= s_int_drdy;
                            
                            --  this was added to avoid re-looping
                            when s_EXT_2_INT_4 =>
                                ss_sync_0 <= '1';
                                ss_ext_mode <= s_ext_mode;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
 
    --  MAIN process
    MAIN:       process(sysClk)
                    variable c: natural := 0;
                    variable times: natural := 0;
                    variable evt: std_logic_vector(2 downto 0) := "000";
                    variable ev2: std_logic_vector(1 downto 0) := "00";
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  setting the various signals
                                    --  external bus controls
                                    r_ext_command_to <= '0';
                                    r_ext_address_to <= (others=>'0');
                                    r_ext_data_to <= (others=>'0');
                                    r_ext_latch <= '0';
                                    --r_ext_ack <= '0';
                                    r_ext_keep <= '0';
                                    r_ext_book <= '0';
                                    r_ext_clear <= '0';
                                    --  internal bus controls
                                    r_int_command_to <= '0';
                                    r_int_address_to <= (others=>'0');
                                    r_int_data_to <= (others=>'0');
                                    r_int_latch <= '0';
                                    --r_int_ack <= '0';
                                    r_int_keep <= '0';
                                    r_int_book <= '0';
                                    r_int_clear <= '0';
                                    --  book
                                    r_int2ext_rdy <= (others=>'0');
                                    r_int2ext_err <= (others=>'0');
                                    --  counters
                                    c := 0;
                                    evt := "000";
                                    --  starting
                                    r_dbg_stage <= 0;
                                    r_stage <= s_IDLE;
                                
                                --  Note
                                --  the internal bus is by default NEVER initiated by a sub-device by its own accord.
                                --  the sub-device instead always tries first to obtain the main bus via the booking procedure, and then it proceeds to occupy the internal bus
                                --  this means that at the end of any given operation, it is safe to check against the internal bus' status to be idle again since no other
                                --  sub device will initiate a status change on it without previous authorization. This will prevent future lockups.
                                when s_IDLE =>
                                    r_dbg_stage <= 1;
                                    --  sorveglio le richieste di booking  oppure sorveglio se il bus esterno si attivasse
                                    evt := (ss_ext_mode & ss_int2ext_flag);
                                    case (evt) is
                                        when "000" =>
                                            --  everything is idling
                                            r_stage <= s_IDLE;
                                        
                                        when "001" =>
                                            --  request to book the ext bus
                                            --  EXT acts as master, sending data to the outside
                                            --  INT acts as slave, receiving data from the mastering sub-device
                                            r_stage <= s_EXT_BOOK_0;
                                        
                                        when "100" =>
                                            --  EXT -> INT transactions
                                            --  EXT acts as slave, receiving data from the outside
                                            --  INT acts as master, sending data to the sub-devices
                                            r_stage <= s_EXT_2_INT_0;
                                        
                                        when "101" =>
                                            --  must tell the sub-devs to stop trying to master the ext
                                            r_stage <= s_BOOK_TERM;
                                        
                                        when "110" =>
                                            --  EXT bus is INACTIVE slave, so we have to keep a watch on it
                                            r_stage <= s_IDLE;
                                        
                                        when "111" =>
                                            --  EXT bus is INACTIVE slave and one of the sub-devs is trying to get a hold, must order them to stop
                                            r_stage <= s_BOOK_TERM;
                                        
                                        when others =>
                                            --  illegal states
                                            r_stage <= s_IDLE;
                                            
                                    end case;
                                
                                when s_BOOK_TERM =>
                                    r_dbg_stage <= 2;
                                    if (ss_int2ext_flag='0') then
                                        r_int2ext_err <= (others=>'0');
                                        r_stage <= s_IDLE;
                                    else
                                        r_int2ext_err <= "1111111";
                                        r_stage <= s_BOOK_TERM;
                                    end if;
                                
                                when s_EXT_BOOK_0 =>
                                    r_dbg_stage <= 3;
                                    evt := ss_sync_0 & ss_ext_booked & ss_ext_rq_error;
                                    case (evt) is
                                        when "100" =>
                                            --  we wait
                                            r_ext_book <= '1';
                                            r_stage <= s_EXT_BOOK_0;
                                        
                                        when "101" =>
                                            --  error during booking attempt
                                            r_stage <= s_EXT_BOOK_1;
                                        
                                        when "110" =>
                                            --  the booking was successful
                                            r_stage <= s_EXT_BOOK_2;
                                        
                                        when others =>
                                            --  illegal condition
                                            r_stage <= s_EXT_BOOK_0;
                                    end case;
                                
                                when s_EXT_BOOK_1 =>
                                    r_dbg_stage <= 4;
                                    if (ss_ext_rq_error='0') then
                                        r_stage <= s_BOOK_TERM;
                                    else
                                        r_ext_book <= '0';
                                        r_stage <= s_EXT_BOOK_1;
                                    end if;   
                                
                                when s_EXT_BOOK_2 =>
                                    r_dbg_stage <= 5;
                                    if (ss_ext_booked='0') then
                                        r_stage <= s_EXT_BOOK_3;
                                    else
                                        r_ext_book <= '0';
                                        r_stage <= s_EXT_BOOK_2;
                                    end if; 
                                
                                when s_EXT_BOOK_3 =>
                                    --  a questo punto il bus EXT e' in book e attende che arrivino mastering requests da parte del sub-bus device
                                    --  devo comunicare al sub-bus che puo partire
                                    r_dbg_stage <= 6;
                                    case (ss_sync_0) is
                                        when '1' =>
                                            if (s_int2ext_req(c)='1') then
                                                --  this was the first sub-dev that issued the request
                                                r_int2ext_rdy(c) <= '1';
                                                r_stage <= s_EXT_BOOK_4;
                                            else
                                                --  going to the next
                                                if (c=6) then
                                                    c := 0;
                                                else
                                                    c := c + 1;
                                                end if;
                                                r_stage <= s_EXT_BOOK_3;
                                            end if;
                                    
                                        when others =>
                                            --  waiting
                                            r_stage <= s_EXT_BOOK_3;
                                    end case;
                                                                    
                                when s_EXT_BOOK_4 =>
                                    r_dbg_stage <= 7;                                    
                                    if (s_int2ext_req(c)='0') then
                                        --  the booker device has lowered its request signal, can go forward
                                        r_stage <= s_INT_2_EXT_0;
                                    else
                                        --  now I lower the ready signal and wait for the booker device to lower its request signal
                                        r_int2ext_rdy(c) <= '0';
                                        r_stage <= s_EXT_BOOK_4;
                                    end if;
                                
                                when s_INT_2_EXT_0 =>
                                    r_dbg_stage <= 8;
                                    --  qui devo aspettare che il sub-master mi mandi dei dati
                                    if ((ss_sync_0='1') and (ss_int_drdy='1')) then
                                        --  receiving data to put forth on the ext bus
                                        r_ext_command_to <= ss_int_command_from;
                                        r_ext_address_to <= ss_int_address_from;
                                        r_ext_data_to <= ss_int_data_from;
                                        r_ext_keep <= (not ss_int_done);
                                        --  we go to latch it
                                        r_stage <= s_INT_2_EXT_1;
                                    else
                                        --  waiting
                                        r_stage <= s_INT_2_EXT_0;
                                    end if;
                                
                                when s_INT_2_EXT_1 =>
                                    r_dbg_stage <= 9;
                                    --  adesso devo aspettare risposta da parte dello slave su ext-bus, quindi:
                                    if ((ss_sync_1='1') and (ss_ext_drdy='1')) then
                                        --  lo slave su ext sta rispondendo
                                        r_int_command_to <= ss_ext_command_from;
                                        r_int_address_to <= ss_ext_address_from;
                                        r_int_data_to <= ss_ext_data_from;
                                        r_int_keep <= (not ss_ext_done);
                                        --  we go to latch it
                                        r_stage <= s_INT_2_EXT_2;
                                    else
                                        --  waiting
                                        r_ext_latch <= '1';
                                        r_stage <= s_INT_2_EXT_1;
                                    end if;
                                
                                when s_INT_2_EXT_2 =>
                                    r_dbg_stage <= 10;
                                    if (ss_int_drdy='0') then
                                        --  response has been sent
                                        r_int_latch <= '0';
                                        r_stage <= s_INT_2_EXT_3;
                                    else
                                        --  sending the response back
                                        r_int_latch <= '1';
                                        r_stage <= s_INT_2_EXT_2;
                                    end if;
                                
                                when s_INT_2_EXT_3 =>
                                    r_dbg_stage <= 11;
                                    --  must now release the ext
                                    if (ss_ext_drdy='0') then
                                        --  the ext is also released, must now see where to go
                                        if (r_int_keep='1') then
                                            --  the slave on the ext bus must send more data
                                            times := times + 1;
                                            r_stage <= s_INT_2_EXT_1;
                                        else
                                            if (r_ext_keep='1') then
                                                --  the master on the int bus must send more data
                                                r_stage <= s_INT_2_EXT_0;
                                            else
                                                --  they are both finished
                                                r_stage <= s_INT_2_EXT_4;
                                            end if;
                                        end if;
                                    else
                                        --  waiting
                                        r_ext_latch <= '0';
                                        r_stage <= s_INT_2_EXT_3;
                                    end if;
                                
                                when s_INT_2_EXT_4 =>
                                    r_dbg_stage <= 12;
                                    --  questo potrebbe dare dei problemi
                                    if ((ss_sync_0='1') and (ss_int_mode="00")) then
                                        if (c=6) then
                                            c := 0;
                                        else
                                            c := c + 1;
                                        end if;
                                        r_stage <= s_IDLE;
                                    else
                                        --  waiting
                                        r_stage <= s_INT_2_EXT_4;
                                    end if;
                                
                                when s_EXT_2_INT_0 =>
                                    r_dbg_stage <= 13;
                                    if ((ss_sync_0='1') and (ss_ext_drdy='1')) then
                                        --  data is here, must forward it to the internal one
                                        r_int_command_to <= ss_ext_command_from;
                                        r_int_address_to <= ss_ext_address_from;
                                        r_int_data_to <= ss_ext_data_from;
                                        r_int_keep <= (not ss_ext_done);
                                        --  going
                                        r_stage <= s_EXT_2_INT_1;
                                    else
                                        --  waiting for data to appear from the external bus
                                        r_stage <= s_EXT_2_INT_0;
                                    end if;
                                
                                when s_EXT_2_INT_1 =>
                                    r_dbg_stage <= 14;
                                    if ((ss_sync_1='1') and (ss_int_drdy='1')) then
                                        --  response is here!
                                        r_dbg_stage <= to_integer(unsigned(ss_int_data_from));
                                        r_ext_command_to <= ss_int_command_from;
                                        r_ext_address_to <= ss_int_address_from;
                                        r_ext_data_to <= ss_int_data_from;
                                        r_ext_keep <= (not ss_int_done);
                                        --  sending the response back
                                        r_stage <= s_EXT_2_INT_2;
                                    else
                                        --  waiting for the sub-dev slave response
                                        r_int_latch <= '1';
                                        r_stage <= s_EXT_2_INT_1;
                                    end if;
                                
                                when s_EXT_2_INT_2 =>
                                    r_dbg_stage <= 15;
                                    if (ss_ext_drdy='0') then
                                        --  response sent
                                        r_ext_latch <= '0';
                                        r_stage <= s_EXT_2_INT_3;
                                    else
                                        --  waiting response
                                        r_ext_latch <= '1';
                                        r_stage <= s_EXT_2_INT_2;
                                    end if;
                                
                                when s_EXT_2_INT_3 =>
                                    r_dbg_stage <= 16;
                                    if (ss_int_drdy='0') then
                                        --  must now see where to go from here
                                        if (r_ext_keep='1') then
                                            --  in this case the slave on the internal bus wants to send more over to the ext, so
                                            r_stage <= s_EXT_2_INT_1;
                                        else
                                            if (r_int_keep='1') then
                                                --  we as masters have more to send over, so
                                                r_stage <= s_EXT_2_INT_0;
                                            else
                                                --  both finished
                                                r_stage <= s_EXT_2_INT_4;
                                            end if;
                                        end if;
                                    else
                                        r_int_latch <= '0';
                                        r_stage <= s_EXT_2_INT_3;
                                    end if;
                                
                                when s_EXT_2_INT_4 =>
                                    r_dbg_stage <= 17;
                                    if ((ss_sync_0='1') and (ss_ext_mode="00")) then
                                        --  going
                                        r_stage <= s_IDLE;
                                    else
                                        --  can go back to idle
                                        r_stage <= s_EXT_2_INT_4;
                                    end if;
                               
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
                
end Behavioral;
