library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bus_bridge is
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
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  sub-system bus interface signals
        sub_bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        sub_bus_strobe_M: inout std_logic;
        sub_bus_strobe_S: inout std_logic;
        sub_bus_keep: inout std_logic;
        sub_bus_rq_lines: in std_logic_vector(6 downto 0);
        sub_bus_grant_lines: out std_logic_vector(6 downto 0);
        sub_bus_busy: out std_logic;
        --  added lines for system bus pre-booking
        sub_bus_req_sys: in std_logic_vector(6 downto 0);   --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        sub_bus_rdy_sys: out std_logic_vector(6 downto 0);  --  this line will go high if the system bus has been granted
        --  debug lines
        dbg_stage: out natural;
        dbg_drdy: out std_logic;
        dbg_done: out std_logic;
        dbg_stage_sysbusint: out natural
    );
end bus_bridge;

architecture Behavioral of bus_bridge is
    --  interface signals
    signal r_bus_command_to: std_logic := '0';
    signal r_bus_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_bus_command_from: std_logic;
    signal s_bus_address_from: std_logic_vector(addr_width-1 downto 0);
    signal s_bus_data_from: std_logic_vector(data_width-1 downto 0);
    signal r_bus_latch: std_logic := '0';
    signal r_bus_ack: std_logic := '0';
    signal r_bus_keep: std_logic := '0';
    signal s_bus_done: std_logic;
    signal s_bus_drdy: std_logic;
    signal r_bus_book: std_logic := '0';
    signal s_bus_booked: std_logic_vector(1 downto 0);
    
    --  sampling signals
    signal ss_bus_command_from: std_logic := '0';
    signal ss_bus_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal ss_bus_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal ss_bus_done: std_logic := '0';
    signal ss_bus_drdy: std_logic := '0';
    signal ss_bus_busy: std_logic := '0';
    signal ss_bus_booked: std_logic_vector(1 downto 0) := "00";
    
    --  device 0 lines
    signal s_sub_bus_grant_0: std_logic := '0';
    signal s_sub_bus_rq_0: std_logic := '0';
    signal s_sub_bus_busy_0: std_logic := '0';
    
    --  arbiter signals
    signal s_sub_bus_rq_lines: std_logic_vector(7 downto 0);
    signal s_sub_bus_grant_lines: std_logic_vector(7 downto 0);
    signal s_sub_bus_busy: std_logic;
    
    --  sub-interface signals
    signal r_sub_bus_command_to: std_logic := '0';
    signal r_sub_bus_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_sub_bus_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_sub_bus_command_from: std_logic;
    signal s_sub_bus_address_from: std_logic_vector(addr_width-1 downto 0);
    signal s_sub_bus_data_from: std_logic_vector(data_width-1 downto 0);
    signal r_sub_bus_latch: std_logic := '0';
    signal r_sub_bus_ack: std_logic := '0';
    signal r_sub_bus_keep: std_logic := '0';
    signal s_sub_bus_done: std_logic;
    signal s_sub_bus_drdy: std_logic;    
    signal r_sub_bus_rdy_sys: std_logic_vector(6 downto 0) := (others=>'0');
    --  sub-interface sampling signals
    signal ss_sub_bus_command_from: std_logic := '0';    
    signal ss_sub_bus_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal ss_sub_bus_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal ss_sub_bus_done: std_logic := '0';
    signal ss_sub_bus_drdy: std_logic := '0';
    signal ss_sub_bus_req_sys: std_logic_vector(6 downto 0) := (others=>'0');
    signal ss_sub_bus_rdy_sys: std_logic_vector(6 downto 0) := (others=>'0');
    signal ss_sub_bus_busy: std_logic := '0';
    
    --  priority encoder
    signal s_prienc_idx: std_logic_vector(2 downto 0);
    signal s_prienc_act: std_logic;
    
    --  state machine
    type t_SM is (
                    s_INIT, s_IDLE, s_SYS_to_SUB_0, s_SYS_to_SUB_1, s_SYS_to_SUB_2, s_SYS_to_SUB_3, s_SYS_to_SUB_4, s_SYS_to_SUB_5, s_SYS_to_SUB_6,
                    s_SUB_to_SYS_0, s_SUB_to_SYS_1, s_SUB_to_SYS_2, s_SUB_to_SYS_3, s_SUB_to_SYS_4, s_SUB_to_SYS_5, s_SUB_to_SYS_6, s_SUB_to_SYS_7
                 );
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    --  debug
    signal r_dbg_stage: natural := 0;
begin
    --  system bus interface
    SYSBUS_INT: entity work.bus_interface(Behavioral)
                    generic map (
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        dev_mem_begin => dev_mem_begin,
                        dev_mem_end => dev_mem_end
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  bus lines and logic
                        bus_lines => bus_lines,
                        bus_strobe_M => bus_strobe_M,
                        bus_strobe_S => bus_strobe_S,
                        bus_keep => bus_keep,
                        --  bus arbiter interface
                        bus_rq => bus_rq,
                        bus_grant => bus_grant,
                        bus_busy => bus_busy,
                        --  interface addr/data signals
                        command_to => r_bus_command_to,
                        command_from => s_bus_command_from,
                        address_to => r_bus_address_to,
                        address_from => s_bus_address_from,
                        data_to => r_bus_data_to,
                        data_from => s_bus_data_from,
                        --  interface sync signals
                        latch => r_bus_latch,
                        done => s_bus_done,
                        drdy => s_bus_drdy,
                        ack => r_bus_ack,
                        keep => r_bus_keep,
                        --  book signals
                        book => r_bus_book,
                        booked => s_bus_booked,
                        --  vediamo il debug qui
                        dbg_stage => dbg_stage_sysbusint
                    );

    --  sub-bus arbiter
    SUBBUS_ARB: entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => 8
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  request lines
                    rq_lines => s_sub_bus_rq_lines,
                    grant_lines => s_sub_bus_grant_lines,
                    busy => s_sub_bus_busy
                );
    
    --  sub-bus interface
    SUBBUS_INT: entity work.bus_interface(Behavioral)
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
                        bus_lines => sub_bus_lines,
                        bus_strobe_M => sub_bus_strobe_M,
                        bus_strobe_S => sub_bus_strobe_S,
                        bus_keep => sub_bus_keep,
                        --  bus arbiter interface
                        bus_rq => s_sub_bus_rq_0,
                        bus_grant => s_sub_bus_grant_0,
                        bus_busy => s_sub_bus_busy,
                        --  interface addr/data signals
                        command_to => r_sub_bus_command_to,
                        command_from => s_sub_bus_command_from,
                        address_to => r_sub_bus_address_to,
                        address_from => s_sub_bus_address_from,
                        data_to => r_sub_bus_data_to,
                        data_from => s_sub_bus_data_from,
                        --  interface sync signals
                        latch => r_sub_bus_latch,
                        done => s_sub_bus_done,
                        drdy => s_sub_bus_drdy,
                        ack => r_sub_bus_ack,
                        keep => r_sub_bus_keep
                    );

    --  Priority Encoder
    PRIENC: entity work.prioenc_mem(Behavioral)
                port map (
                    snapshot => ss_sub_bus_req_sys,
                    prioidx => s_prienc_idx,
                    act => s_prienc_act
                );

    --  Bridge Sampler and Driver processes
    SAMP:   process(sysClk)
            begin
                if (falling_edge(sysClk)) then
                    case (r_stage) is
                        when s_INIT =>
                            --  system bus sampling
                            ss_bus_command_from <= '0';
                            ss_bus_address_from <= (others=>'0');
                            ss_bus_data_from <= (others=>'0');
                            ss_bus_done <= '0';
                            ss_bus_drdy <= '0';
                            ss_bus_busy <= '0';
                            ss_bus_booked <= "00";
                            --  sub-system bus sampling
                            ss_sub_bus_command_from <= '0';
                            ss_sub_bus_address_from <= (others=>'0');
                            ss_sub_bus_data_from <= (others=>'0');
                            ss_sub_bus_done <= '0';
                            ss_sub_bus_drdy <= '0';
                            ss_sub_bus_req_sys <= (others=>'0');
                            ss_sub_bus_rdy_sys <= (others=>'0');
                            ss_sub_bus_busy <= '0';
                            
                        when s_IDLE =>
                            ss_bus_command_from <= s_bus_command_from;
                            ss_bus_address_from <= s_bus_address_from;
                            ss_bus_data_from <= s_bus_data_from;
                            ss_bus_drdy <= s_bus_drdy;
                            ss_bus_done <= s_bus_done;
                            ss_sub_bus_req_sys <= sub_bus_req_sys;
                        
                        when s_SYS_to_SUB_1 =>
                            ss_sub_bus_command_from <= s_sub_bus_command_from;
                            ss_sub_bus_address_from <= s_sub_bus_address_from;
                            ss_sub_bus_data_from <= s_sub_bus_data_from;
                            ss_sub_bus_drdy <= s_sub_bus_drdy;
                            ss_sub_bus_done <= s_sub_bus_done;
                        
                        when s_SYS_to_SUB_2 =>
                            ss_bus_drdy <= s_bus_drdy;
                        
                        when s_SYS_to_SUB_3 =>
                            ss_sub_bus_drdy <= s_sub_bus_drdy;
                        
                        when s_SYS_to_SUB_4 =>
                            ss_sub_bus_done <= s_sub_bus_done;
                            
                        when s_SYS_to_SUB_5 =>
                            ss_bus_busy <= bus_busy;
                            ss_sub_bus_busy <= s_sub_bus_busy;
                        
                        when s_SYS_to_SUB_6 =>
                            ss_bus_command_from <= s_bus_command_from;
                            ss_bus_address_from <= s_bus_address_from;
                            ss_bus_data_from <= s_bus_data_from;
                            ss_bus_drdy <= s_bus_drdy;
                            ss_bus_done <= s_bus_done;
                            ss_bus_busy <= bus_busy;
                        
                        --  sub to sys
                        when s_SUB_to_SYS_0 =>
                            ss_bus_booked <= s_bus_booked;
                        
                        when s_SUB_to_SYS_1 =>
                            ss_sub_bus_drdy <= s_sub_bus_drdy;
                            ss_sub_bus_req_sys <= sub_bus_req_sys;
                            ss_sub_bus_command_from <= s_sub_bus_command_from;
                            ss_sub_bus_address_from <= s_sub_bus_address_from;
                            ss_sub_bus_data_from <= s_sub_bus_data_from;
                            ss_sub_bus_done <= s_sub_bus_done;
                        
                        when s_SUB_to_SYS_2 =>
                            ss_bus_drdy <= s_bus_drdy;
                            ss_bus_command_from <= s_bus_command_from;
                            ss_bus_address_from <= s_bus_address_from;
                            ss_bus_data_from <= s_bus_data_from;
                            ss_bus_done <= s_bus_done;
                        
                        when s_SUB_to_SYS_3 =>
                            ss_bus_drdy <= s_bus_drdy;
                            ss_bus_done <= s_bus_done;
                        
                        when s_SUB_to_SYS_4 =>
                            ss_sub_bus_drdy <= s_sub_bus_drdy;
                        
                        when s_SUB_to_SYS_5 =>
                            ss_bus_done <= s_bus_done;
                        
                        when others =>
                            null;
                    end case;
                end if;
            end process SAMP;
    
    MAIN:   process(sysClk)
                variable cond: std_logic_vector(1 downto 0) := "00";
                variable dIdx: natural := 0;
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>
                                --  debug
                                r_dbg_stage <= 0;
                                --  initialization stage of the bus-bridge
                                r_bus_command_to <= '0';
                                r_bus_address_to <= (others=>'0');
                                r_bus_data_to <= (others=>'0');
                                r_bus_latch <= '0';
                                r_bus_ack <= '0';
                                r_bus_keep <= '0';
                                r_bus_book <= '0';
                                --  sub-bus
                                r_sub_bus_command_to <= '0';
                                r_sub_bus_address_to <= (others=>'0');
                                r_sub_bus_data_to <= (others=>'0');
                                r_sub_bus_latch <= '0';
                                r_sub_bus_ack <= '0';
                                r_sub_bus_keep <= '0';
                                r_sub_bus_rdy_sys <= (others=>'0');
                                --  going
                                r_stage <= s_IDLE;
                        
                            when s_IDLE =>
                                --  debug
                                r_dbg_stage <= 1;
                                --  here we wait for the system bus to send us something or from one of the internal devices
                                --  to ask ownership of the system bus
                                --  must be watchful for ss_bus_drdy and ss_sub_bus_drdy
                                cond := ss_bus_drdy & s_prienc_act;
                                case (cond) is
                                    --  the system bus is being driven, so
                                    when "10" =>
                                        r_stage <= s_SYS_to_SUB_0;
                                    when "11" =>
                                        r_stage <= s_SYS_to_SUB_0;
                                    
                                    --  it means that one or more of the sub-devs wants to book the system bus
                                    when "01" =>
                                        r_bus_book <= '1';
                                        r_stage <= s_SUB_to_SYS_0;
                                    
                                    when others =>
                                        --  nothing is happening
                                        r_stage <= s_IDLE;
                                end case;
                                
                            --------------------------------------------------------------------------------------------------
                            --
                            --  SYS to SUB case
                            --
                            --------------------------------------------------------------------------------------------------
                            when s_SYS_to_SUB_0 =>
                                --  debug
                                r_dbg_stage <= 2;
                                --  the system bus is sending data from the interface, hence
                                r_sub_bus_command_to <= ss_bus_command_from;
                                r_sub_bus_address_to <= ss_bus_address_from;
                                r_sub_bus_data_to <= ss_bus_data_from;
                                r_sub_bus_keep <= not(ss_bus_done);
                                --  we can now forward the word on to the sub-system and wait
                                r_sub_bus_latch <= '1';
                                r_stage <= s_SYS_to_SUB_1;
                    
                            when s_SYS_to_SUB_1 =>
                                --  debug
                                r_dbg_stage <= 3;
                                --  we must wait for the sub-bus to respond, so:
                                if (ss_sub_bus_drdy='1') then
                                    --  the sub-dev has responded, hence we must set-up a response for the system-bus
                                    --  for which we're working as a SLAVE device
                                    r_bus_command_to <= ss_sub_bus_command_from;
                                    r_bus_address_to <= ss_sub_bus_address_from;
                                    r_bus_data_to <= ss_sub_bus_data_from;
                                    r_bus_keep <= not(ss_sub_bus_done);
                                    --  now, we must send this response back to the system-bus
                                    --  in the meanwhile, the sub-sys is kept locked by having ACK low
                                    r_bus_latch <= '1';
                                    r_stage <= s_SYS_to_SUB_2;
                                else
                                    --  waiting for a response
                                    r_stage <= s_SYS_to_SUB_1;
                                end if;
                    
                            when s_SYS_to_SUB_2 =>
                                --  debug
                                r_dbg_stage <= 4;
                                if (ss_bus_drdy='0') then
                                    --  this means it has received our data for now, so we keep now the system-bus
                                    --  transceiver locked down
                                    r_bus_latch <= '0';
                                    --  we now turn back to the sub-sys
                                    r_sub_bus_ack <= '1';
                                    r_stage <= s_SYS_to_SUB_3;
                                else
                                    r_stage <= s_SYS_to_SUB_2;
                                end if;
                            
                            when s_SYS_to_SUB_3 =>
                                --  debug
                                r_dbg_stage <= 5;
                                --  here we have to wait for the sub-sys to de-acknowledge and see where we have to go
                                if (ss_sub_bus_drdy='0') then
                                    --  it has de-acknowledged, so
                                    r_sub_bus_ack <= '0';
                                    --  must see if we have more response-byte to send over
                                    if (ss_sub_bus_done='0') then
                                        --  we indeed have more, so:
                                        r_stage <= s_SYS_to_SUB_1;
                                    else
                                        --  in this case instead the sub-slave has sent everything it has
                                        --  we latch it down
                                        r_sub_bus_latch <= '0';
                                        r_stage <= s_SYS_to_SUB_4;
                                    end if;
                                else
                                    r_stage <= s_SYS_to_SUB_3;
                                end if;
                    
                            when s_SYS_to_SUB_4 =>
                                --  debug
                                r_dbg_stage <= 6;
                                if (ss_sub_bus_done='0') then
                                    --  now we have to see if the sys-master has more for us
                                    if (ss_bus_done='0') then
                                        --  the master has more transactions that could also be for us, so
                                        r_stage <= s_SYS_to_SUB_6;
                                    else
                                        --  the master has no more, we must wait until both the sys-bus and the sub-slave become inactive
                                        r_stage <= s_SYS_to_SUB_5;
                                    end if;
                                else
                                    r_stage <= s_SYS_to_SUB_4;
                                end if;
                    
                            when s_SYS_to_SUB_5 =>
                                --  debug
                                r_dbg_stage <= 7;
                                --  in this case we wait
                                if (ss_sub_bus_busy='0') then
                                    --  bridge disengaged
                                    r_stage <= s_IDLE;
                                else
                                    --  waiting
                                    r_stage <= s_SYS_to_SUB_5;
                                end if;
                    
                            when s_SYS_to_SUB_6 =>
                                --  debug
                                r_dbg_stage <= 8;
                                cond := ss_bus_drdy & ss_bus_busy;
                                case (cond) is
                                    --  new data has arrived
                                    when "10" =>
                                        r_stage <= s_SYS_to_SUB_0;
                                    when "11" =>
                                        r_stage <= s_SYS_to_SUB_0;
                                    
                                    --  waiting here since it could be for us
                                    when "01" =>
                                        r_stage <= s_SYS_to_SUB_6;
                                    
                                    --  the bus has disengaged so it wasn't for us
                                    when "00" =>
                                        r_stage <= s_IDLE;
                                    
                                    when others =>
                                        r_stage <= s_SYS_to_SUB_6;
                                end case;
                    
                            --------------------------------------------------------------------------------------------------
                            --
                            --  SUB to SYS case
                            --
                            --------------------------------------------------------------------------------------------------
                            when s_SUB_to_SYS_0 =>
                                --  in this case we have requested a book on the bus, must see
                                r_dbg_stage <= 9;
                                case (ss_bus_booked) is
                                    when "10" =>
                                        --  booking succesful, the system bus is mastered by us
                                        dIdx := to_integer(unsigned(s_prienc_idx));
                                        r_sub_bus_rdy_sys(dIdx) <= '1';
                                        r_bus_book <= '0';
                                        --  now to wait for the sub-dev master to send things
                                        r_stage <= s_SUB_to_SYS_1;
                                    
                                    when "01" =>
                                        --  booking failed, cannot proceed. We must be slaves
                                        r_bus_book <= '0';
                                        r_stage <= s_IDLE;
                                    
                                    when others =>
                                        --  we must wait
                                        r_stage <= s_SUB_to_SYS_0;
                                end case;
                            
                            when s_SUB_to_SYS_1 =>
                                --  now, we are waiting for the sub-master to start sending data
                                --r_dbg_stage <= 10;
                                cond := ss_sub_bus_req_sys(dIdx) & ss_sub_bus_drdy;
                                r_dbg_stage <= to_integer(unsigned(cond));
                                case (cond) is
                                    when "01" =>
                                        --  we can go forward and get the data to send over to the bus
                                        r_sub_bus_rdy_sys(dIdx) <= '0';
                                        --  getting stuff from the sub-bus to the system bus
                                        r_bus_command_to <= ss_sub_bus_command_from;
                                        r_bus_address_to <= ss_sub_bus_address_from;
                                        r_bus_data_to <= ss_sub_bus_data_from;
                                        r_bus_keep <= not(ss_sub_bus_done);
                                        --  starting the transaction
                                        r_bus_latch <= '1';
                                        r_stage <= s_SUB_to_SYS_2;
                                
                                    when others =>
                                        --  waiting
                                        r_stage <= s_SUB_to_SYS_1;
                                end case;
                            
                            when s_SUB_to_SYS_2 =>
                                --  now we must wait for the slave on the system bus to answer back with data
                                --  the core idea is that before returning data to the sub-slave, to place the remote device
                                --  in a known state.
                                r_dbg_stage <= 11;
                                --  waiting for the slave
                                if (ss_bus_drdy='1') then
                                    --  data is here!
                                    r_sub_bus_command_to <= ss_bus_command_from;
                                    r_sub_bus_address_to <= ss_bus_address_from;
                                    r_sub_bus_data_to <= ss_bus_data_from;
                                    r_sub_bus_keep <= not(ss_bus_done);
                                    --  before latching the response on the sub-bus, we handle the system bus properly
                                    --  doing an ack
                                    r_bus_ack <= '1';
                                    r_stage <= s_SUB_to_SYS_3;
                                else
                                    --  have to wait
                                    r_stage <= s_SUB_to_SYS_2;
                                end if;

                            when s_SUB_to_SYS_3 =>
                                --  checking now
                                if (ss_bus_drdy='0') then
                                    --  the slave has gone forward
                                    r_bus_ack <= '0';
                                    if (ss_bus_done='0') then
                                        --  this means that the slave still has data for us, so
                                        r_jump <= s_SUB_to_SYS_2;
                                    else
                                        --  the slave has no more data for us
                                        r_jump <= s_SUB_to_SYS_5;
                                    end if;
                                    --  first we must deliver the answer to the sub-master
                                    r_stage <= s_SUB_to_SYS_4;
                                else
                                    --  waiting for slave
                                    r_stage <= s_SUB_to_SYS_3;
                                end if;

                            when s_SUB_to_SYS_4 =>
                                --  latching the response
                                if (ss_sub_bus_drdy='0') then
                                    --  the sub-master has acknowledged the receival of the data
                                    r_sub_bus_latch <= '0';
                                    r_stage <= r_jump;
                                else
                                    --  keeping the latch active
                                    r_sub_bus_latch <= '1';
                                    r_stage <= s_SUB_to_SYS_4;
                                end if;

                            when s_SUB_to_SYS_5 =>
                                --  we wait here until
                                if (ss_bus_done='0') then
                                    --  now we must see where to go
                                    if (ss_sub_bus_done='0') then
                                        --  the sub-master has more transactions in mind
                                        r_stage <= s_SUB_to_SYS_1;
                                    else
                                        --  no more transactions
                                        r_stage <= s_IDLE;
                                    end if;
                                else
                                    --  waiting
                                    r_bus_latch <= '0';                                  
                                    r_stage <= s_SUB_to_SYS_5;
                                end if;
                            
                            when others =>
                                r_stage <= r_stage;
                        end case;
                    end if;
                end if;            
            end process MAIN;

    --  continuous assignments
    s_sub_bus_rq_lines(7 downto 1) <= sub_bus_rq_lines;
    s_sub_bus_rq_lines(0) <= s_sub_bus_rq_0;
    sub_bus_grant_lines <= s_sub_bus_grant_lines(7 downto 1);
    s_sub_bus_grant_0 <= s_sub_bus_grant_lines(0);
    s_sub_bus_busy_0 <= s_sub_bus_busy;
    sub_bus_busy <= s_sub_bus_busy;
        
    --  outputs
    sub_bus_rdy_sys <= r_sub_bus_rdy_sys;
    dbg_stage <= r_dbg_stage;
    dbg_drdy <= ss_bus_drdy;
    dbg_done <= ss_bus_done;
    
end Behavioral;
