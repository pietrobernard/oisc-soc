library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
------------------------------------------------------------------------------------------------------------------------------------------------------------
--  bus_interface_v2
--
entity bus_interface_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device data
        dev_mem_begin: integer := 0;
        dev_mem_end: integer := 0;
        --  debug
        dev_id: natural := 0
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  bus lines and logic
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        --  bus arbiter interface
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  interface addr/data signals
        command_to: in std_logic;                                       --  command to send to the bus this interface is connected to
        command_from: out std_logic;                                    --  command coming from said bus
        address_to: in std_logic_vector(addr_width-1 downto 0);         --  address of the remote interface we want to send the command+data to
        address_from: out std_logic_vector(addr_width-1 downto 0);      --  address coming from said bus
        data_to: in std_logic_vector(data_width-1 downto 0);            --  data to send to the bus to the remote interface
        data_from: out std_logic_vector(data_width-1 downto 0);         --  data coming from said bus
        --  interface sync signals
        latch: in std_logic;                                            --  controls transmission / response
        done: out std_logic;                                            --  goes high when operation is completed
        drdy: out std_logic;                                            --  goes high when new data arrives from the far end
        keep: in std_logic;                                             --  must be high synchronous to latch, if 1 it means the writing end will send more after this
        --  booking facilities
        book: in std_logic := '0';                                      --  book signal to try and get hold of the bus before actually starting a transaction
        booked: out std_logic := '0';                                   --  status of the book operation: goes to 1 if the bus has been booked (book must then be lowered)
        rq_error: out std_logic;                                        --  if booking / mastering the bus fails, this goes up
        interface_mode: out std_logic_vector(1 downto 0);               --  current status of the interface: 00 = inactive, 01 = master, 10 = active slave, 11 = monitoring slave
        clear: in std_logic;                                            --  if this is high and the booking/mastering fails, the bus request is withdrawn from the bus arbiter
        --  debug output
        dbg_stage: out natural
    );
end bus_interface_v2;

architecture Behavioral of bus_interface_v2 is
    --  BUS LINES DRIVERS
    signal r_bus_dir: std_logic := '0';
    signal r_bus_word_to: std_logic_vector(bus_width-1 downto 0) := (others=>'0');
    signal s_bus_word_from: std_logic_vector(bus_width-1 downto 0) := (others=>'0');
    
    --  STROBE M DRIVERS
    signal r_strobe_M_dir: std_logic := '0';
    signal r_to_strobe_M: std_logic := '0';
    signal s_from_strobe_M: std_logic := '0';
    
    --  STROBE S DRIVERS
    signal r_strobe_S_dir: std_logic := '0';
    signal r_to_strobe_S: std_logic := '0';
    signal s_from_strobe_S: std_logic := '0';
    
    --  KEEP LINE
    signal r_keep_dir: std_logic := '0';
    signal r_to_keep: std_logic := '0';
    signal s_from_keep: std_logic := '0';
    
    --  DONE_S LINE
    signal r_to_done_S: std_logic := '0';
    signal s_from_done_S: std_logic := '0';
        
    --  INTERFACE
    signal s_int_latch: std_logic := '0';
    signal r_int_done: std_logic := '0';
    signal r_int_drdy: std_logic := '0';
    signal s_int_keep: std_logic := '0';
    signal s_int_book: std_logic := '0';
    signal r_int_booked: std_logic := '0';
    signal s_int_clear: std_logic := '0';
    
    --  Sampler Synchronizers
    signal ss_sync_0: std_logic := '0';
    signal ss_sync_1: std_logic := '0';
    
    --  Helper Registers
    signal r_busreq: std_logic := '0';
    signal s_busgnt: std_logic := '0';
    signal s_busbsy: std_logic := '0';
    signal ss_from_strobe_M: std_logic := '0';
    signal ss_from_strobe_S: std_logic := '0';
    signal ss_bus_word_from: std_logic_vector(bus_width-1 downto 0) := (others=>'0');
    signal ss_from_keep: std_logic := '0';
    signal ss_from_done_S: std_logic := '0';
    
    --  signals that sample from the interface input
    signal s_int_command_to: std_logic := '0';
    signal s_int_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal s_int_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    
    --  signals that drive the interface output
    signal r_int_command_from: std_logic := '0';
    signal r_int_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_int_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_rq_error: std_logic := '0';
    signal r_int_mode: std_logic_vector(1 downto 0) := "00";
    
    --  STATE MACHINE
    type t_SM is (s_INIT, s_IDLE, s_SLAVE_MONITOR, s_SLAVE_MONITOR_CHECK,
                    s_SLAVE_0, s_SLAVE_1, s_SLAVE_2, s_SLAVE_3, s_SLAVE_4, s_SLAVE_5, s_SLAVE_6, s_SLAVE_7, s_SLAVE_8, s_SLAVE_9,
                    s_MASTER_0, s_MASTER_1, s_MASTER_2, s_MASTER_3, s_MASTER_4, s_MASTER_5, s_MASTER_6, s_MASTER_7, s_MASTER_8,
                    s_BOOK_0, s_BOOK_1, s_ABORT_MASTER_0, s_ABORT_MASTER_1, s_ABORT_BOOK_0, s_ABORT_BOOK_1);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
begin
    --  bus line driver
    BUS_LINES_DRIVER:       entity work.inout_port(Behavioral)
                                generic map (nbits => bus_width)
                                port map (
                                    dir => r_bus_dir,
                                    io => bus_lines,
                                    data_to => r_bus_word_to,
                                    data_from => s_bus_word_from
                                );

    --  bus strobe lines
    BUS_STROBE_M_DRIVER:    entity work.inout_port(Behavioral)
                                generic map (nbits => 1)
                                port map (
                                    dir => r_strobe_M_dir,
                                    io(0) => bus_strobe_M,
                                    data_to(0) => r_to_strobe_M,
                                    data_from(0) => s_from_strobe_M
                                );
    BUS_STROBE_S_DRIVER:    entity work.inout_port(Behavioral)
                                generic map (nbits => 1)
                                port map (
                                    dir => r_strobe_S_dir,
                                    io(0) => bus_strobe_S,
                                    data_to(0) => r_to_strobe_S,
                                    data_from(0) => s_from_strobe_S
                                );
    
    --  keep line driver
    KEEP_DRIVER:            entity work.inout_port(Behavioral)
                                generic map (nbits => 1)
                                port map (
                                    dir => r_keep_dir,
                                    io(0) => bus_keep,
                                    data_to(0) => r_to_keep,
                                    data_from(0) => s_from_keep
                                );
    
    --  bus done S driver
    BUS_DONE_S_DRIVER:      entity work.inout_port(Behavioral)
                                generic map ( nbits=>1 )
                                port map (
                                    dir => r_strobe_S_dir,
                                    io(0) => bus_done_S,
                                    data_to(0) => r_to_done_S,
                                    data_from(0) => s_from_done_S
                                );

    --  processes
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                s_int_latch <= '0';
                                s_int_command_to <= '0';
                                s_int_address_to <= (others=>'0');
                                s_int_data_to <= (others=>'0');
                                s_int_keep <= '0';
                                s_int_book <= '0';
                                s_int_clear <= '0';
                                s_busgnt <= '0';
                                s_busbsy <= '0';
                                ss_from_strobe_M <= '0';
                                ss_from_strobe_S <= '0';
                                ss_from_keep <= '0';
                                ss_bus_word_from <= (others=>'0');
                                --  syncs
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                                
                            when s_IDLE =>
                                --	sampling the interface
                                s_int_latch <= latch;
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                                --	sampling the bus
                                ss_from_strobe_M <= s_from_strobe_M;
                                ss_from_strobe_S <= '0';
                                s_int_book <= book;
                                --  syncs
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s_ABORT_BOOK_0 =>
                                s_int_book <= book;
                            
                            when s_ABORT_BOOK_1 =>
                            --  synchronizers
                                ss_sync_0 <= '0';
                                s_int_clear <= clear;
                            
                            when s_ABORT_MASTER_0 =>
                                s_int_latch <= latch;
                            
                            when s_ABORT_MASTER_1 =>
                                s_int_clear <= clear;
                                ss_sync_0 <= '0';
                            
                            when s_BOOK_0 =>
                                --  synchronizers
                                ss_sync_0 <= '1';                                
                                --  signals
                                s_busgnt <= bus_grant;
                                s_busbsy <= bus_busy;
                            
                            when s_BOOK_1 =>                            
                                ss_sync_0 <= '0';
                                s_int_book <= book;
                            
                            when s_MASTER_0 =>
                                s_busgnt <= bus_grant;
                                s_busbsy <= bus_busy;
                                ss_sync_0 <= '1';
                            
                            when s_MASTER_1 =>
                                ss_sync_0 <= '0';
                            
                            when s_MASTER_2 =>
                                s_int_latch <= latch;
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                                ss_sync_0 <= '1';
                            
                            when s_MASTER_3 =>
                                ss_from_strobe_S <= s_from_strobe_S;
                                ss_sync_0 <= '0';
                            
                            when s_MASTER_4 =>
                                ss_from_strobe_S <= s_from_strobe_S;
                            
                            when s_MASTER_5 =>
                                ss_bus_word_from <= s_bus_word_from;
                                ss_from_strobe_S <= s_from_strobe_S;
                                ss_from_keep <= s_from_keep;
                                ss_sync_0 <= '1';
                            
                            when s_MASTER_6 =>
                                s_int_latch <= latch;
                                ss_sync_0 <= '0';
                            
                            when s_MASTER_7 =>
                                ss_from_strobe_S <= s_from_strobe_S;
                            
                            when s_MASTER_8 =>
                                ss_sync_0 <= '1';
                                s_busgnt <= bus_grant;
                                s_busbsy <= bus_busy;
                            
                            when s_SLAVE_1 =>
                                ss_bus_word_from <= s_bus_word_from;
                                ss_from_strobe_M <= s_from_strobe_M;
                                ss_from_keep <= s_from_keep;
                                s_busbsy <= bus_busy;
                                ss_from_done_S <= s_from_done_S;
                                ss_sync_1 <= '1';
                            
                            when s_SLAVE_MONITOR =>
                                s_busbsy <= bus_busy;
                                --ss_from_strobe_M <= s_from_strobe_M;  --  OLD ONE
                                ss_from_done_S <= s_from_done_S;
                                ss_sync_0 <= '1';
                                ss_sync_1 <= '0';
                            
                            when s_SLAVE_MONITOR_CHECK =>
                                ss_from_done_S <= s_from_done_S;
                                ss_sync_0 <= '0';
                            
                            when s_SLAVE_2 =>
                                ss_sync_1 <= '0';
                                                        
                            when s_SLAVE_3 =>
                                s_int_latch <= latch;
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                            
                            when s_SLAVE_4 =>
                                s_int_latch <= latch;
                            
                            when s_SLAVE_5 =>
                                ss_from_strobe_M <= s_from_strobe_M;
                            
                            when s_SLAVE_6 =>
                                ss_from_strobe_M <= s_from_strobe_M;                                                       
                            
                            when s_SLAVE_8 =>
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                                ss_from_strobe_M <= s_from_strobe_M;
                            
                            when s_SLAVE_9 =>
                                ss_sync_0 <= '1';
                                s_busbsy <= bus_busy;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable c: natural := 0;
                    variable addr: natural := 0;
                    variable addr_now: natural := 0;
                    variable cond: std_logic_vector(2 downto 0) := "000";
                    variable cnd2: std_logic_vector(1 downto 0) := "00";
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  bus control
                                    c := 0;
                                    addr := 0;
                                    cond := "000";
                                    r_bus_dir <= '0';
                                    r_bus_word_to <= (others=>'0');
                                    r_strobe_M_dir <= '0';
                                    r_to_strobe_M <= '0';
                                    r_strobe_S_dir <= '0';
                                    r_to_strobe_S <= '0';
                                    r_keep_dir <= '0';
                                    r_to_keep <= '0';
                                    r_to_done_S <= '0';
                                    r_int_done <= '0';
                                    r_int_drdy <= '0';
                                    r_busreq <= '0';
                                    r_int_command_from <= '0';
                                    r_int_address_from <= (others=>'0');
                                    r_int_data_from <= (others=>'0');
                                    r_int_booked <= '0';
                                    r_rq_error <= '0';
                                    r_int_mode <= "00";
                                    --  going
                                    dbg_stage <= 0;
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  we can have: latch request, book request or an event from the bus we're connected to
                                    cond := (s_int_latch & ss_from_strobe_M & s_int_book);
                                    dbg_stage <= 1;
                                    case (cond) is
                                        --  now the various cases
                                        when "000" =>
                                            --  idling case
                                            r_int_mode <= "00";
                                            r_rq_error <= '0';
                                            r_stage <= s_IDLE;
                                        
                                        --  ACTION CONDITIONS
                                        when "001" =>
                                            --  we want to book the bus we're connected to in order to execute transaction later on the bus
                                            r_stage <= s_BOOK_0;
                                        
                                        when "010" =>
                                            --  we are receiving an event from the bus we're connected to
                                            r_stage <= s_SLAVE_0;
                                        
                                        when "100" =>
                                            --  we want to execute a transaction on the bus we're connected to immediately
                                            r_stage <= s_MASTER_0;
                                        
                                        --  CONCURRENCY OF CONDITIONS
                                        when "011" =>
                                            --  in this case we have to terminate the booking attempt first
                                            r_stage <= s_ABORT_BOOK_0;
                                        
                                        when "110" =>
                                            --  in this case we have to terminate the latchin attempt first
                                            r_stage <= s_ABORT_MASTER_0;
                                        
                                        --  other cases are illegal, hence
                                        when others =>
                                            r_rq_error <= '1';
                                            r_stage <= s_IDLE;
                                    end case;
                                
                                --  the abort cases
                                when s_ABORT_BOOK_0 =>
                                    dbg_stage <= 2;
                                    if (s_int_book='0') then
                                        r_rq_error <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_rq_error <= '1';
                                        r_stage <= s_ABORT_BOOK_0;
                                    end if;
                                
                                when s_ABORT_BOOK_1 =>
                                    dbg_stage <= 3;
                                    if (s_int_clear='1') then
                                        --  clear the booking from the arbiter
                                        r_busreq <= '0';
                                    else
                                        --  remain booked in the arbiter
                                        r_busreq <= '1';
                                    end if;
                                    r_stage <= s_ABORT_BOOK_0;
                                
                                when s_ABORT_MASTER_0 =>
                                    dbg_stage <= 4;
                                    if (s_int_latch='0') then
                                        r_rq_error <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_rq_error <= '1';
                                        r_stage <= s_ABORT_MASTER_0;
                                    end if;
                                
                                when s_ABORT_MASTER_1 =>
                                    dbg_stage <= 5;
                                    if (s_int_clear='1') then
                                        --  clear the booking from the arbiter
                                        r_busreq <= '0';
                                    else
                                        --  remain booked in the arbiter
                                        r_busreq <= '1';
                                    end if;
                                    r_stage <= s_ABORT_MASTER_0;
                                
                                --  bus booking procedures
                                when s_BOOK_0 =>
                                    dbg_stage <= 6;
                                    --  we try to book the bus
                                    cond := ss_sync_0 & s_busgnt & s_busbsy;
                                    case (cond) is
                                        when "100" =>
                                            --  waiting for bus booking
                                            r_busreq <= '1';
                                            r_stage <= s_BOOK_0;
                                        
                                        when "101" =>
                                            --  fail to get the bus
                                            r_stage <= s_ABORT_BOOK_1;
                                        
                                        when "111" =>
                                            --  bus obtained succesfully
                                            r_stage <= s_BOOK_1;
                                        
                                        when others =>
                                            --  illegal condition or not yet ready
                                            r_stage <= s_BOOK_0;
                                    end case;
                                
                                when s_BOOK_1 =>
                                    dbg_stage <= 7;
                                    if (s_int_book='0') then
                                        r_int_booked <= '0';
                                        r_stage <= s_MASTER_1;
                                    else
                                        r_int_booked <= '1';
                                        r_stage <= s_BOOK_1;
                                    end if;
                                
                                --  master procedure
                                when s_MASTER_0 =>
                                    dbg_stage <= 8;
                                    cond := ss_sync_0 & s_busgnt & s_busbsy;
                                    case (cond) is
                                        when "100" =>
                                            --  waiting for bus booking
                                            r_busreq <= '1';
                                            r_stage <= s_MASTER_0;
                                        
                                        when "101" =>
                                            --  fail to get the bus
                                            r_stage <= s_ABORT_MASTER_1;
                                        
                                        when "111" =>
                                            --  bus obtained succesfully
                                            r_stage <= s_MASTER_1;
                                        
                                        when others =>
                                            --  illegal condition or still not ready
                                            r_stage <= s_MASTER_0;
                                    end case;
                                
                                when s_MASTER_1 =>
                                    dbg_stage <= 9;
                                    --  preparing the bus
                                    r_to_strobe_M <= '0';                                    
                                    r_to_keep <= '0';
                                    --  setting directions
                                    r_bus_dir <= '1';
                                    r_keep_dir <= '1';
                                    --  setting strobe drives
                                    r_strobe_S_dir <= '0';
                                    r_strobe_M_dir <= '1';
                                    --  setting mode
                                    r_int_mode <= "01";
                                    --  going
                                    r_stage <= s_MASTER_2;
                                
                                when s_MASTER_2 =>
                                    dbg_stage <= 10;
                                    if ((ss_sync_0='1') and (s_int_latch='1')) then
                                        --  placing input data in the bus drivers
                                        r_bus_word_to(31) <= s_int_command_to;
                                        r_bus_word_to(30 downto data_width) <= s_int_address_to;
                                        r_bus_word_to(data_width-1 downto 0) <= s_int_data_to;
                                        r_to_keep <= s_int_keep;
                                        --  starting
                                        r_stage <= s_MASTER_3;
                                    else
                                        --  waiting for the interface to send the data we need to transmit
                                        r_to_strobe_M <= '0';
                                        r_stage <= s_MASTER_2;
                                    end if;
                                
                                when s_MASTER_3 =>
                                    dbg_stage <= 11;
                                    --dbg_stage <= to_integer(unsigned(r_bus_word_to(data_width-1 downto 0)));
                                    if (ss_from_strobe_S='1') then
                                        --  we need to give the slave the bus, so:
                                        r_bus_dir <= '0';
                                        r_keep_dir <= '0';
                                        r_stage <= s_MASTER_4;
                                    else
                                        --  waiting for the slave to ask for the bus
                                        r_to_strobe_M <= '1';
                                        r_stage <= s_MASTER_3;
                                    end if;
                                
                                when s_MASTER_4 =>
                                    dbg_stage <= 12;
                                    if (ss_from_strobe_S='0') then
                                        --  the slave has acknowledged the bus change
                                        r_stage <= s_MASTER_5;
                                    else
                                        --  signalling
                                        r_to_strobe_M <= '0';
                                        r_stage <= s_MASTER_4;
                                    end if;
                                
                                when s_MASTER_5 =>
                                    dbg_stage <= 13;
                                    if ((ss_sync_0='1') and (ss_from_strobe_S='1')) then
                                        --  here is the slave's response, need to put it out
                                        r_int_command_from <= ss_bus_word_from(31);
                                        r_int_address_from <= ss_bus_word_from(30 downto data_width);
                                        r_int_data_from <= ss_bus_word_from(data_width-1 downto 0);
                                        --dbg_stage <= to_integer(unsigned(ss_bus_word_from(data_width-1 downto 0)));
                                        r_int_done <= (not ss_from_keep);
                                        --  showing
                                        r_stage <= s_MASTER_6;
                                    else
                                        --  waiting for the slave to send response
                                        r_stage <= s_MASTER_5;
                                    end if;
                                
                                when s_MASTER_6 =>
                                    dbg_stage <= 14;
                                    if (s_int_latch='0') then
                                        --  we can show down
                                        r_int_drdy <= '0';
                                        r_stage <= s_MASTER_7;
                                    else
                                        --  showing
                                        r_int_drdy <= '1';
                                        r_stage <= s_MASTER_6;
                                    end if;
                                
                                when s_MASTER_7 =>
                                    dbg_stage <= 15;
                                    if (ss_from_strobe_S='0') then
                                        --  now I need to see what I have to do
                                        cnd2 := r_to_keep & (not r_int_done);
                                        case (cnd2) is
                                            when "00" =>
                                                --  we have nothing more, can terminate the transaction, so we release the bus on our end
                                                r_stage <= s_MASTER_8;
                                            
                                            when "01"|"11" =>
                                                --  the slave has more data for us, so we leave the bus as it is and go for it
                                                r_stage <= s_MASTER_3;
                                                
                                            when "10" =>
                                                --  we have more to send over, so we have to lower our strobe too
                                                r_stage <= s_MASTER_1;

                                        end case;
                                    else
                                        --  rising the strobe M to acked the response
                                        r_to_strobe_M <= '1';
                                        r_stage <= s_MASTER_7;
                                    end if;
                                
                                when s_MASTER_8 =>
                                    dbg_stage <= 16;
                                    if ((ss_sync_0='1') and (s_busgnt='0') and (s_busbsy='0')) then
                                        r_strobe_M_dir <= '0';
                                        r_bus_dir <= '0';
                                        r_keep_dir <= '0';
                                        r_int_mode <= "00";
                                        r_stage <= s_IDLE;
                                    else
                                        r_to_strobe_M <= '0';
                                        r_busreq <= '0';
                                        r_stage <= s_MASTER_8;
                                    end if;
                                
                                --  slave procedure
                                when s_SLAVE_0 =>
                                    dbg_stage <= 17;
                                    --  preparing the bus
                                    r_to_strobe_S <= '0';
                                    r_to_keep <= '0';
                                    r_to_done_S <= '0';
                                    --  setting directions
                                    r_bus_dir <= '0';
                                    r_keep_dir <= '0';
                                    --  setting strobe drives
                                    r_strobe_S_dir <= '0';
                                    r_strobe_M_dir <= '0';
                                    --  going
                                    r_stage <= s_SLAVE_1;
                                
                                when s_SLAVE_1 =>
                                    dbg_stage <= 18;
                                    --  we wait for an event by the master, hence
                                    case (ss_sync_1) is
                                        when '1' =>
                                            if (ss_from_strobe_M='1') then
                                                --  master is sending data, we have to check against the address to see if it is for us
                                                addr := to_integer(unsigned(ss_bus_word_from(30 downto data_width)));
                                                if ((addr >= dev_mem_begin) and (addr <= dev_mem_end)) then
                                                    --  this transmission is for us
                                                    r_int_mode <= "10";
                                                    r_strobe_S_dir <= '1';
                                                    r_stage <= s_SLAVE_2;
                                                else
                                                    --  this transmission is not for us
                                                    r_int_mode <= "11";
                                                    r_strobe_S_dir <= '0';
                                                    r_stage <= s_SLAVE_MONITOR;
                                                end if;
                                            else
                                                --  this is added
                                                if (s_busbsy='1') then
                                                    --  waiting for the master
                                                    r_stage <= s_SLAVE_1;
                                                else
                                                    --  master has disengaged
                                                    r_jump <= s_SLAVE_9;
                                                    r_stage <= s_SLAVE_8;
                                                end if;
                                            end if;
                                    
                                        when others =>
                                            --  not yet ready
                                            r_stage <= s_SLAVE_1;
                                    end case;
                                                              
                                when s_SLAVE_MONITOR =>
                                    --  nuova versione che utilizza il bus_done_S
                                    dbg_stage <= 19;
                                    cond := ss_sync_0 & s_busbsy & ss_from_done_S;
                                    case (cond) is
                                        when "100"|"101" =>
                                            --  the bus has gone offline
                                            r_jump <= s_SLAVE_9;
                                            r_stage <= s_SLAVE_8;
                                        
                                        when "110" =>
                                            --  bus is active and done S is still low
                                            r_int_mode <= "11";
                                            r_stage <= s_SLAVE_MONITOR;
                                        
                                        when "111" =>
                                            --  the done S signal has risen, so
                                            r_stage <= s_SLAVE_MONITOR_CHECK;
                                        
                                        when others =>
                                            --  still not ready
                                            r_stage <= s_SLAVE_MONITOR;
                                    end case;
                                
                                when s_SLAVE_MONITOR_CHECK =>
                                    dbg_stage <= 28;
                                    if (ss_from_done_S='0') then
                                        --  when it goes off it means the old slave has disengaged
                                        --  also I have the guarantee that the strobe M is low, so:
                                        r_stage <= s_SLAVE_0;
                                    else
                                        r_stage <= s_SLAVE_MONITOR_CHECK;
                                    end if;
                                    
                                when s_SLAVE_2 =>
                                    dbg_stage <= 20;
                                    --  gathering the data from the master and shoving it out
                                    r_int_command_from <= ss_bus_word_from(31);
                                    r_int_address_from <= ss_bus_word_from(30 downto data_width);
                                    r_int_data_from <= ss_bus_word_from(data_width-1 downto 0);
                                    r_int_done <= (not ss_from_keep);
                                    --  showing
                                    r_stage <= s_SLAVE_3;
                                
                                when s_SLAVE_3 =>
                                    dbg_stage <= 21;
                                    if (s_int_latch='1') then
                                        --  the interface has acknowledged the data and has sent a response to send back to the master
                                        r_bus_word_to(31) <= s_int_command_to;
                                        r_bus_word_to(30 downto data_width) <= s_int_address_to;
                                        r_bus_word_to(data_width-1 downto 0) <= s_int_data_to;
                                        r_to_keep <= s_int_keep;
                                        --  going
                                        r_stage <= s_SLAVE_4;
                                    else
                                        --  waiting for the interface to receive the data
                                        r_int_drdy <= '1';
                                        r_stage <= s_SLAVE_3;
                                    end if;
                                
                                when s_SLAVE_4 =>
                                    dbg_stage <= 22;
                                    dbg_stage <= to_integer(unsigned(r_bus_word_to(data_width-1 downto 0)));                                    
                                    if (s_int_latch='0') then
                                        --  going
                                        r_stage <= s_SLAVE_5;
                                    else
                                        --  lowering the drdy
                                        r_int_drdy <= '0';
                                        r_stage <= s_SLAVE_4;
                                    end if;
                                
                                when s_SLAVE_5 =>
                                    dbg_stage <= 23;
                                    --  now we signal the bus that we have data ready, but first we need to reverse the bus
                                    if (ss_from_strobe_M='0') then
                                        --  the bus is ours
                                        r_to_strobe_S <= '0';
                                        r_stage <= s_SLAVE_6;
                                    else
                                        --  signalling we want the bus
                                        r_to_strobe_S <= '1';
                                        r_stage <= s_SLAVE_5;
                                    end if;
                                
                                when s_SLAVE_6 =>
                                    dbg_stage <= 24;
                                    if (ss_from_strobe_M='1') then
                                        --  the master has acknowledged it
                                        r_to_strobe_S <= '0';
                                        --  bus commutation
                                        r_bus_dir <= '0';
                                        r_keep_dir <= '0';
                                        --  going
                                        r_stage <= s_SLAVE_7;
                                    else
                                        --  placing the data
                                        r_bus_dir <= '1';
                                        r_keep_dir <= '1';
                                        --  signalling
                                        r_to_strobe_S <= '1';
                                        r_stage <= s_SLAVE_6;
                                    end if;
                                
                                when s_SLAVE_7 =>
                                    dbg_stage <= 25;
                                    --  let's see what to do
                                    cnd2 := r_to_keep & (not r_int_done);
                                    case (cnd2) is
                                        when "00" =>
                                            --  we have nothing more, can terminate the transaction, so we release the bus on our end
                                            r_to_done_S <= '1';
                                            r_jump <= s_SLAVE_9;
                                            r_stage <= s_SLAVE_8;
                                        
                                        when "01" =>
                                            --  the master has more data to send and it could be for us. We need to release the bus and signal the master we're ready and then jump
                                            r_to_done_S <= '1';
                                            r_jump <= s_SLAVE_0;
                                            r_stage <= s_SLAVE_8;
                                        
                                        when "10"|"11" =>
                                            --  we have more to send to the master so we do not change the bus and we start again
                                            r_stage <= s_SLAVE_3;
                                            
                                    end case;
                                
                                when s_SLAVE_8 =>
                                    dbg_stage <= 26;
                                    if (ss_from_strobe_M='0') then
                                        --  going
                                        r_stage <= r_jump;
                                    else
                                        --  waiting for the master
                                        r_stage <= s_SLAVE_8;
                                    end if;
                                
                                when s_SLAVE_9 =>
                                    dbg_stage <= 27;
                                    --  we make sure everything is off
                                    if ((ss_sync_0='1') and (s_busbsy='0')) then
                                        --  exit
                                        r_strobe_S_dir <= '0';
                                        r_to_done_S <= '0';
                                        r_int_mode <= "00";
                                        r_stage <= s_IDLE;
                                    else
                                        --  waiting
                                        --r_strobe_S_dir <= '0';    --  moved up
                                        r_stage <= s_SLAVE_9;
                                    end if;
                                
                                when others =>
                                    r_stage <= s_IDLE;
                                
                            end case;
                        end if;
                    end if;
                end process MAIN;

    --  assignments
    interface_mode <= r_int_mode;
    bus_rq <= r_busreq;
    command_from <= r_int_command_from;
    address_from <= r_int_address_from;
    data_from <= r_int_data_from;
    done <= r_int_done;
    drdy <= r_int_drdy;
    booked <= r_int_booked;
    rq_error <= r_rq_error;
                 
end Behavioral;
