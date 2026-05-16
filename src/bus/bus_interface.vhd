library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--  changelog:
--  4/04/25 : reduced the doubleregistry: using ss only for event signals and not for the whole when possible to reduce logic levels and thus negative slack
entity bus_interface is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device data
        dev_mem_begin: integer := 0;
        dev_mem_end: integer := 0
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  bus lines and logic
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        --  bus arbiter interface
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  interface addr/data signals
        command_to: in std_logic;
        command_from: out std_logic;
        address_to: in std_logic_vector(addr_width-1 downto 0);
        address_from: out std_logic_vector(addr_width-1 downto 0);
        data_to: in std_logic_vector(data_width-1 downto 0);
        data_from: out std_logic_vector(data_width-1 downto 0);
        --  interface sync signals
        latch: in std_logic;    --  a bus word is latched when this goes high
        done: out std_logic;    --  goes high when operation is completed
        drdy: out std_logic;    --  goes high when new data arrives from the far end
        ack: in std_logic;      --  must go high to signal the gathering of the received data
        keep: in std_logic;     --  must be high synchronous to latch
        book: in std_logic := '0';  --  book signal to try and get hold of the bus before actually starting a transaction
        booked: out std_logic_vector(1 downto 0) := "00";   --  booked signal
        --  debug output
        dbg_stage: out natural;
        dbg_gen: out std_logic_vector(7 downto 0)
    );
end bus_interface;

architecture Behavioral of bus_interface is
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
        
    --  INTERFACE
    signal s_int_latch: std_logic := '0';
    signal r_int_done: std_logic := '0';
    signal r_int_drdy: std_logic := '0';
    signal s_int_ack: std_logic := '0';
    signal s_int_keep: std_logic := '0';
    signal s_int_book: std_logic := '0';
    signal r_int_booked: std_logic_vector(1 downto 0) := "00";
    
    --  Helper Registers
    signal r_busreq: std_logic := '0';
    signal s_busgnt: std_logic := '0';
    signal s_busbsy: std_logic := '0';
    signal ss_from_strobe_M: std_logic := '0';
    signal ss_from_strobe_S: std_logic := '0';
    signal ss_bus_word_from: std_logic_vector(bus_width-1 downto 0) := (others=>'0');
    signal ss_from_keep: std_logic := '0';
    
    --  signals that sample from the interface input
    signal s_int_command_to: std_logic := '0';
    signal s_int_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal s_int_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    
    --  signals that drive the interface output
    signal r_int_command_from: std_logic := '0';
    signal r_int_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_int_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    
    --  STATE MACHINE
    type t_SM is (s_INIT, s_IDLE, s_SLAVE_0, s_SLAVE_1, s_SLAVE_2, s_SLAVE_3, s_SLAVE_4, s_SLAVE_5, s_SLAVE_6,
                    s_MASTER_0, s_MASTER_1, s_MASTER_2, s_MASTER_3, s_MASTER_4, s_MASTER_5, s_MASTER_6, s_MASTER_7, s_MASTER_8, s_MASTER_9,
                    s_BOOK_0, s_BOOK_1, s_BOOK_2);
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

    --  PROCESSES
    SAMPLER:    process(sysClk)
    
                begin
                    --  e se campionassi al falling edge invece?
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                --  samplers from bus
                                ss_bus_word_from <= (others=>'0');
                                ss_from_strobe_M <= '0';
                                ss_from_strobe_S <= '0';
                                ss_from_keep <= '0';
                                s_int_latch <= '0';
                                s_int_ack <= '0';
                                s_int_keep <= '0';
                                s_busgnt <= '0';
                                s_busbsy <= '0';
                                s_int_command_to <= '0';
                                s_int_address_to <= (others=>'0');
                                s_int_data_to <= (others=>'0');
                                s_int_book <= '0';
                        
                            when s_IDLE =>
                                --  sampling these signals for the slave mode
                                ss_from_strobe_M <= s_from_strobe_M;
                                ss_bus_word_from <= s_bus_word_from;
                                ss_from_keep <= s_from_keep;
                                --  sampling for the master mode
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                                s_int_latch <= latch;
                                --  booking mode
                                s_int_book <= book;
                        
                            when s_MASTER_0 =>
                                --  let's see
                                s_busgnt <= bus_grant;
                                s_busbsy <= bus_busy;
                            
                            when s_MASTER_2 =>
                                --  let's sample
                                ss_from_strobe_S <= s_from_strobe_S;
                            
                            when s_MASTER_3 =>
                                --  let's sample
                                ss_from_strobe_S <= s_from_strobe_S;
                            
                            when s_MASTER_4 =>
                                --  let's sample
                                ss_from_strobe_S <= s_from_strobe_S;
                                ss_bus_word_from <= s_bus_word_from;
                                ss_from_keep <= s_from_keep;
                            
                            when s_MASTER_5 =>
                                ss_from_strobe_S <= s_from_strobe_S;
                                s_int_ack <= ack;
                            
                            when s_MASTER_6 =>
                                s_int_latch <= latch;
                                s_int_ack <= ack;
                            
                            when s_MASTER_7 =>
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                                s_int_latch <= latch;
                            
                            when s_MASTER_8 =>
                                s_busgnt <= bus_grant;
                                s_busbsy <= bus_busy;
                            
                            when s_MASTER_9 =>
                                s_int_ack <= ack;
                            
                            --  SLAVE
                            when s_SLAVE_1 =>
                                s_busbsy <= bus_busy;
                            
                            when s_SLAVE_2 =>
                                ss_from_strobe_M <= s_from_strobe_M;
                            
                            when s_SLAVE_3 =>
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                                s_int_latch <= latch;
                            
                            when s_SLAVE_4 =>
                                s_int_latch <= latch;
                                ss_from_strobe_M <= s_from_strobe_M;
                            
                            when s_SLAVE_5 =>
                                ss_from_strobe_M <= s_from_strobe_M;
                            
                            when s_SLAVE_6 =>
                                ss_from_strobe_M <= s_from_strobe_M;
                                ss_bus_word_from <= s_bus_word_from;
                                ss_from_keep <= s_from_keep;
                            
                            when s_BOOK_0 =>
                                s_busgnt <= bus_grant;
                                s_busbsy <= bus_busy;
                            
                            when s_BOOK_1 =>
                                s_int_book <= book;
                                s_int_command_to <= command_to;
                                s_int_address_to <= address_to;
                                s_int_data_to <= data_to;
                                s_int_keep <= keep;
                                s_int_latch <= latch;
                            
                            when s_BOOK_2 =>
                                s_int_book <= book;
                            
                            when others =>
                                null;
                                                        
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable mas: std_logic_vector(2 downto 0) := "000";
                    variable evt: std_logic_vector(1 downto 0) := "00";
                    variable c: integer := 0;
                    variable addr: integer := 0;
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
                                    r_bus_dir <= '0';
                                    r_bus_word_to <= (others=>'0');
                                    r_strobe_M_dir <= '0';
                                    r_to_strobe_M <= '0';
                                    r_strobe_S_dir <= '0';
                                    r_to_strobe_S <= '0';
                                    r_keep_dir <= '0';
                                    r_to_keep <= '0';
                                    r_int_done <= '0';
                                    r_int_drdy <= '0';
                                    r_busreq <= '0';
                                    r_int_command_from <= '0';
                                    r_int_address_from <= (others=>'0');
                                    r_int_data_from <= (others=>'0');
                                    r_int_booked <= "00";
                                    --  going
                                    dbg_stage <= 0;
                                    r_stage <= s_IDLE;
                            
                                when s_IDLE =>
                                    --  when idling we must check whether the bus becomes active or the interface triggers
                                    --  we need to check two things
                                    r_bus_dir <= '0';
                                    r_strobe_M_dir <= '0';
                                    r_strobe_S_dir <= '0';
                                    r_keep_dir <= '0';
                                    r_to_keep <= '0';
                                    r_to_strobe_M <= '0';
                                    r_to_strobe_S <= '0';
                                    r_bus_word_to <= (others=>'0');
                                    --  checking where we are
                                    dbg_stage <= 1;
                                    --evt := ss_from_strobe_M & s_int_latch;
                                    mas := s_int_book & ss_from_strobe_M & s_int_latch;
                                    dbg_gen(1 downto 0) <= (ss_from_strobe_M & s_int_latch);
                                    case (mas) is
                                        --  if an event occurrs on the bus, it has the precedence over everything else: SLAVE mode
                                        when "010" | "011" | "110" | "111" =>
                                            r_stage <= s_SLAVE_0;
                                        
                                        --  if an event occurrs on the interface, we see if we manage to go into MASTER mode
                                        when "001" | "101" =>
                                            r_busreq <= '1';
                                            r_stage <= s_MASTER_0;
                                        
                                        --  book request has the lowest priority
                                        when "100" =>
                                            r_busreq <= '1';
                                            r_stage <= s_BOOK_0;
                                        
                                        --  remain here if nothing happens
                                        when "000" =>
                                            r_stage <= s_IDLE;
                                    end case;
                            
                                ----------------------------------------------------
                                --  BOOK MODE
                                ----------------------------------------------------
                                when s_BOOK_0 =>
                                    --  in this case, the bus is simply booked, meaning
                                    evt := (s_busgnt & s_busbsy);
                                    case (evt) is
                                        --  in this case the bus has been given to us so it is booked!
                                        when "10" | "11" =>
                                            r_int_booked <= "10";
                                            r_stage <= s_BOOK_1;
                                        
                                        when "01" =>
                                            --  the bus has been given to somebody else
                                            r_busreq <= '0';
                                            r_int_booked <= "01";
                                            r_stage <= s_BOOK_2;
                                        
                                        when others =>
                                            --  waiting
                                            r_int_booked <= "00";
                                            r_stage <= s_BOOK_0;
                                            
                                    end case;
                                
                                when s_BOOK_1 =>
                                    --  in this case we wait for the interface to switch over main mode, so
                                    evt := (s_int_book & s_int_latch);
                                    case (evt) is
                                        when "01" =>
                                            --  we go
                                            r_stage <= s_MASTER_0;
                                        
                                        when others =>
                                            --  we wait
                                            r_stage <= s_BOOK_1;
                                    end case;
                                
                                when s_BOOK_2 =>
                                    if (s_int_book='0') then
                                        --  must enter slave mode instead
                                        r_int_booked <= "00";
                                        r_stage <= s_SLAVE_0;
                                    else
                                        r_stage <= s_BOOK_2;
                                    end if;
                            
                                ----------------------------------------------------
                                --  MASTER MODE
                                ----------------------------------------------------
                                when s_MASTER_0 =>
                                    evt := (s_busgnt & s_busbsy);
                                    dbg_stage <= 2;
                                    case (evt) is
                                        when "10" | "11" =>
                                            --  configuring directions
                                            r_bus_dir <= '1';
                                            r_strobe_M_dir <= '1';
                                            r_strobe_S_dir <= '0';
                                            r_keep_dir <= '1';
                                            r_to_strobe_M <= '0';
                                            r_to_keep <= '0';
                                            --  going
                                            r_stage <= s_MASTER_1;
                                                                                                                        
                                        when "01" =>
                                            --  bus has been granted to someone else, must enter slave mode instead
                                            r_busreq <= '0';
                                            r_stage <= s_SLAVE_0;
                                        
                                        when others =>
                                            --  waiting
                                            r_stage <= s_MASTER_0;
                                    end case;
                            
                                when s_MASTER_1 =>
                                    dbg_stage <= 3;
                                    --  here we start the transmission
                                    r_bus_word_to(31) <= s_int_command_to;
                                    r_bus_word_to(30 downto data_width) <= s_int_address_to;
                                    r_bus_word_to(data_width-1 downto 0) <= s_int_data_to;
                                    r_to_keep <= s_int_keep;
                                    r_to_strobe_M <= '1';
                                    --  and now we wait for the slave to ack
                                    r_stage <= s_MASTER_2;
                            
                                when s_MASTER_2 =>
                                    dbg_stage <= 4;
                                    --  the slave acknowledges the data reception by raising strobe_S high
                                    if (ss_from_strobe_S='1') then
                                        --  we now tell to the slave that the bus can be driven by it
                                        r_bus_dir <= '0';
                                        r_keep_dir <= '0';
                                        r_to_strobe_M <= '0';
                                        r_stage <= s_MASTER_3;
                                    else
                                        --  waiting
                                        r_stage <= s_MASTER_2;
                                    end if;
                            
                                when s_MASTER_3 =>
                                    dbg_stage <= 5;
                                    --  now we wait for the slave to ACK that it can drive the bus
                                    if (ss_from_strobe_S='0') then
                                        --  the slave has acked
                                        r_stage <= s_MASTER_4;
                                    else
                                        --  waiting
                                        r_stage <= s_MASTER_3;
                                    end if;
                                
                                when s_MASTER_4 =>
                                    dbg_stage <= 6;
                                    --  waiting for the slave to respond
                                    if (ss_from_strobe_S='1') then
                                        --  present the response to the interface
                                        r_int_command_from <= s_bus_word_from(31);
                                        r_int_address_from <= s_bus_word_from(30 downto data_width);
                                        r_int_data_from <= s_bus_word_from(data_width-1 downto 0);
                                        --  then if the slave has no more to send
                                        if (ss_from_keep='0') then
                                            r_int_done <= '1';
                                        else
                                            r_int_done <= '0';
                                        end if;
                                        r_int_drdy <= '1';
                                        r_to_strobe_M <= '1';
                                        r_stage <= s_MASTER_5;
                                    else
                                        --  waiting
                                        r_stage <= s_MASTER_4;
                                    end if;
                            
                                when s_MASTER_5 =>
                                    dbg_stage <= 7;
                                    --  we wait for the slave to ACK that we've got the data and to do the bus switch
                                    if ((ss_from_strobe_S='0') and (s_int_ack='1')) then
                                        --  now the slave is waiting that we pull strobe_M low but before we do it, we must see where we are
                                        if (r_int_done='0') then
                                            --  it means that the slave's response is comprised of multiple bytes and that it still has to send us more
                                            r_int_drdy <= '0';
                                            r_stage <= s_MASTER_9;
                                        else
                                            --  it means that the slave has no more data to send us for this transaction, hence the slave has given back the bus to us
                                            r_to_strobe_M <= '0';
                                            r_int_drdy <= '0';
                                            --  configuring the various jumps
                                            if (r_to_keep='1') then
                                                --  we have more transactions
                                                r_bus_dir <= '1';
                                                r_keep_dir <= '1';
                                                r_jump <= s_MASTER_7;
                                            else
                                                --  we are done using the bus
                                                r_bus_dir <= '0';
                                                r_keep_dir <= '0';
                                                r_jump <= s_MASTER_8;
                                            end if;
                                            --  going
                                            r_stage <= s_MASTER_6;
                                        end if;
                                    else
                                        --  waiting
                                        r_stage <= s_MASTER_5;
                                    end if;
                                                               
                                when s_MASTER_6 =>
                                    dbg_stage <= 8;
                                    --  now we have pulled M low and we have to see where to go
                                    if ((s_int_latch='0') and (s_int_ack='0')) then
                                        --  once the interface has un-latched, we're ready to start another transaction
                                        r_int_done <= '0';
                                        r_stage <= r_jump;
                                    else
                                        --  waiting for the interface to un-latch
                                        r_stage <= s_MASTER_6;
                                    end if;
                            
                                when s_MASTER_7 =>
                                    dbg_stage <= 9;
                                    if (s_int_latch='1') then
                                        r_stage <= s_MASTER_1;
                                    else
                                        r_stage <= s_MASTER_7;
                                    end if;
                                
                                when s_MASTER_8 =>
                                    dbg_stage <= 10;
                                    if (s_busgnt='0') then
                                        --  once the bus has been released, we can exit
                                        r_stage <= s_IDLE;
                                    else
                                        --  releasing the system bus
                                        r_busreq <= '0';
                                        r_stage <= s_MASTER_8;
                                    end if;
                            
                                when s_MASTER_9 =>
                                    dbg_stage <= 11;
                                    if (s_int_ack='0') then
                                        --  the master is ready for further transactions
                                        r_to_strobe_M <= '0';
                                        r_stage <= s_MASTER_4;
                                    else
                                        --  waiting
                                        r_stage <= s_MASTER_9;
                                    end if;
                            
                                ----------------------------------------------------
                                --  SLAVE MODE
                                ----------------------------------------------------
                                when s_SLAVE_0 =>
                                    dbg_stage <= 12;
                                    addr := to_integer(unsigned(s_bus_word_from(30 downto data_width)));--to_integer(unsigned(ss_bus_word_from(30 downto data_width)));
                                    if ((addr >= dev_mem_begin) and (addr <= dev_mem_end)) then
                                        --  it is for us! we have to present the data to the interface's output
                                        r_int_command_from <= s_bus_word_from(31); -- ss_bus_word_from(31);
                                        r_int_address_from <= s_bus_word_from(30 downto (data_width)); --ss_bus_word_from(30 downto (data_width));
                                        r_int_data_from <= s_bus_word_from(data_width-1 downto 0); --ss_bus_word_from(data_width-1 downto 0);
                                        --  let's see
                                        if (ss_from_keep='1') then
                                            r_int_done <= '0';
                                        else
                                            r_int_done <= '1';
                                        end if;
                                        r_int_drdy <= '1';
                                        --  now to go
                                        --  setting up
                                        r_bus_dir <= '0';
                                        r_strobe_M_dir <= '0';
                                        r_strobe_S_dir <= '1';
                                        r_keep_dir <= '0';
                                        r_to_strobe_S <= '0';
                                        r_stage <= s_SLAVE_2;
                                    else
                                        --  it is not for us, so we must wait until the transaction(s) finish
                                        r_stage <= s_SLAVE_1;
                                    end if;
                            
                                when s_SLAVE_1 =>
                                    dbg_stage <= 13;
                                    --  remaining here until the bus is busy
                                    if (s_busbsy='0') then
                                        --  as soon as the bus is free again, go back to idling
                                        r_int_done <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        --  waiting for the bus to become inactive
                                        r_stage <= s_SLAVE_1;
                                    end if;
                            
                                when s_SLAVE_2 =>
                                    dbg_stage <= 14;
                                    --  we first have to signal the master we've got the data
                                    if (ss_from_strobe_M='0') then
                                        --  the master has received our ACK and is givin the bus to us to send the response
                                        r_to_strobe_S <= '0';
                                        r_bus_dir <= '1';
                                        r_keep_dir <= '1';
                                        r_stage <= s_SLAVE_3;
                                    else
                                        --  signalling the master we've got the data
                                        r_to_strobe_S <= '1';
                                        r_stage <= s_SLAVE_2;
                                    end if;
                            
                                when s_SLAVE_3 =>
                                    dbg_stage <= 15;
                                    --  we must now wait for the interface to act in order to get the response
                                    if (s_int_latch='1') then
                                        --  the interface has sent the data, we must put it over the bus
                                        r_bus_word_to(31) <= s_int_command_to;
                                        r_bus_word_to(30 downto data_width) <= s_int_address_to;
                                        r_bus_word_to(data_width-1 downto 0) <= s_int_data_to;
                                        r_to_keep <= s_int_keep;
                                        --  configuring
                                        r_int_drdy <= '0';
                                        r_to_strobe_S <= '1';
                                        r_stage <= s_SLAVE_4;
                                    else
                                        --  waiting
                                        r_int_drdy <= '1';
                                        r_stage <= s_SLAVE_3;
                                    end if;
                            
                                when s_SLAVE_4 =>
                                    dbg_stage <= 16;
                                    --  synchronizing both the bus and the interface
                                    if ((s_int_latch='0') and (ss_from_strobe_M='1')) then
                                        --  now we need to check where we are
                                        r_to_strobe_S <= '0';
                                        if (r_to_keep='0') then
                                            --  we have no more response bytes to send over, ut the master might
                                            --  releasing the bus
                                            r_bus_dir <= '0';
                                            r_keep_dir <= '0';
                                            if (ss_from_keep='0') then
                                                --  the master has no more
                                                r_jump <= s_SLAVE_1;
                                            else
                                                --  the master will initiate another transaction, so we must release the bus
                                                r_jump <= s_SLAVE_6;
                                            end if;
                                        else
                                            --  we still have response bytes to send over
                                            --r_int_drdy <= '1';
                                            r_jump <= s_SLAVE_3;
                                        end if;
                                        --  going
                                        r_stage <= s_SLAVE_5;
                                    else
                                        --  waiting
                                        r_stage <= s_SLAVE_4;
                                    end if;
                            
                                when s_SLAVE_5 =>
                                    dbg_stage <= 17;
                                    --  waiting for the master to go down
                                    if (ss_from_strobe_M='0') then
                                        --  going to next stage
                                        r_stage <= r_jump;
                                    else
                                        --  waiting for the master to get ready
                                        r_stage <= s_SLAVE_5;
                                    end if;
                            
                                when s_SLAVE_6 =>
                                    dbg_stage <= 18;
                                    --  now the strobes are down and the master will now drive the bus again
                                    if (ss_from_strobe_M='1') then
                                        --  the master is sending new word
                                        r_stage <= s_SLAVE_0;
                                    else
                                        --  waiting for the master
                                        r_stage <= s_SLAVE_6;
                                    end if;
                            
                            end case;
                        end if;
                    end if;
                end process MAIN;

    --  assignments
    bus_rq <= r_busreq;
    command_from <= r_int_command_from;
    address_from <= r_int_address_from;
    data_from <= r_int_data_from;
    done <= r_int_done;
    drdy <= r_int_drdy;
    booked <= r_int_booked;
        
end Behavioral;
