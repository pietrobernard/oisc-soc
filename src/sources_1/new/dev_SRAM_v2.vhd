library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dev_SRAM_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 2;
        dev_mem_begin: integer := 0;    --  start of memory space for the UART device
        dev_mem_end: integer := 0       --  end of memory space for the UART device
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  system bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  hardware lines
        DATA: inout std_logic_vector(data_width-1 downto 0);
        SRAM_TRXDIR: out std_logic;
        SRAM_TRXOE: out std_logic;
        SRAM_CE: out std_logic;
        SRAM_OE: out std_logic;
        SRAM_WE: out std_logic;
        SRAM_LH: out std_logic;
        RAL_L: out std_logic;
        RAL_H: out std_logic;
        --  debug
        dbg_dev: out natural;
        dbg_dev_int: out natural
    );
end dev_SRAM_v2;

architecture Behavioral of dev_SRAM_v2 is
    --  control registers
    signal r_dev_in_cmd: std_logic := '0';
    signal r_dev_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_dev_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_dev_in_keep: std_logic := '0';
    signal r_dev_in_latch: std_logic := '0';
    
    -- output signals from bus interface
    signal s_dev_out_cmd: std_logic;
    signal s_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_dev_out_drdy: std_logic;
    signal s_dev_out_done: std_logic;
    signal s_dev_err: std_logic;
    signal s_dev_chg: std_logic;
    
    --  sampling signals
    signal ss_dev_out_cmd: std_logic;
    signal ss_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_dev_out_drdy: std_logic;
    signal ss_dev_out_done: std_logic;
    signal ss_dev_err: std_logic;
    signal ss_dev_chg: std_logic;
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_A_0, s_A_1, s_A_0_l0, s_A_0_l1, s_W_0, s_W_P, s_R_0, s_R_1, s_P_1, s_REG_0);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    --  hardware driving signals
    signal r_TDIR: std_logic := '1';    -- 0 : sram to fpga, 1 : fpga to sram
    signal r_TOE: std_logic := '1';     -- 1 : isolation, 0 : transceiver active
    signal r_CE: std_logic := '1';      -- 1 : disable
    signal r_OE: std_logic := '1';      -- 1 : disable
    signal r_WE: std_logic := '1';      -- 1 : disable
    signal r_LH: std_logic := '0';      -- 0 : addresses 0x0000 to 0xffff | 1 : addresses 0x10000 to 0x1ffff
    signal r_RAL_L: std_logic := '1';   -- 1 : follow input, 0 : latch in value
    signal r_RAL_H: std_logic := '1';   -- 1 : follow input, 0 : latch in value
    
    --  DATA port signals
    signal s_data_from: std_logic_vector(data_width-1 downto 0);
    signal r_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
                    
    --  helper signals
    signal sram_address: std_logic_vector(16 downto 0) := (others=>'0');
    signal sram_delta: std_logic_vector(14 downto 0) := (others=>'0');    
    
    --  timing constants in unit of clock cycles (10 ns)
    constant latch_tsu: natural := 4;
    constant latch_th: natural := 2;
begin
    --  assignments
    SRAM_TRXDIR <= r_TDIR;
    SRAM_TRXOE <= r_TOE;
    SRAM_CE <= r_CE;
    SRAM_OE <= r_OE;
    SRAM_WE <= r_WE;
    SRAM_LH <= r_LH;
    RAL_L <= r_RAL_L;
    RAL_H <= r_RAL_H;
    
    --  data port driver
    DATA_DRV:   entity work.inout_port(Behavioral)
                generic map (
                    nbits => 8
                ) port map (
                    io => DATA,
                    data_to => r_data_to,
                    data_from => s_data_from,
                    dir => r_TDIR
                );

    BUS_DEV:    entity work.dev_v2(Behavioral)
                generic map (
                    dev_id => dev_id,
                    dev_mem_begin => dev_mem_begin,
                    dev_mem_end => dev_mem_end                    
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_done_S => bus_done_S,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  external interface signals
                    dev_in_cmd => r_dev_in_cmd,
                    dev_in_addr => r_dev_in_addr,
                    dev_in_data => r_dev_in_data,
                    dev_in_keep => r_dev_in_keep,
                    dev_in_latch => r_dev_in_latch,
                    dev_out_cmd => s_dev_out_cmd,
                    dev_out_addr => s_dev_out_addr,
                    dev_out_data => s_dev_out_data,
                    dev_out_drdy => s_dev_out_drdy,
                    dev_out_done => s_dev_out_done,
                    dev_err => s_dev_err,
                    dev_chg => s_dev_chg,
                    --  debug
                    dbg_stage => dbg_dev,
                    devbus_interface => dbg_dev_int
                );

    --  SRAM device must drive the static ram and also generate appropriate events
    --  when areas of memory belonging to specific devices are being written to/read from.
    --  the sram thus requires addresses 0x00000 to 0x1ffff
    --  these addresses must be virtual so that they access the s-ram directly.
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_dev_out_cmd <= '0';
                                ss_dev_out_addr <= (others=>'0');
                                ss_dev_out_data <= (others=>'0');
                                ss_dev_out_drdy <= '0';
                                ss_dev_out_done <= '0';
                                ss_dev_err <= '0';
                                ss_dev_chg <= '0';
                        
                            when s_IDLE =>
                                ss_dev_out_cmd <= s_dev_out_cmd;
                                ss_dev_out_addr <= s_dev_out_addr;
                                ss_dev_out_data <= s_dev_out_data;
                                ss_dev_out_drdy <= s_dev_out_drdy;
                                ss_dev_out_done <= s_dev_out_done;
                                ss_dev_err <= s_dev_err;
                                ss_dev_chg <= s_dev_chg;
                        
                            when s_REG_0 =>
                                ss_dev_chg <= s_dev_chg;
                            
                            when s_P_1 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when others =>
                                null;
                                
                        end case;
                    end if;
                end process SAMPLER;
    
    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                    variable phys_address: natural := 0;
                    variable bc: natural := 0;
                    variable clockCounter: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  bus interface
                                    r_dev_in_cmd <= '0';
                                    r_dev_in_addr <= (others=>'0');
                                    r_dev_in_data <= (others=>'0');
                                    r_dev_in_keep <= '0';
                                    r_dev_in_latch <= '0';
                                    --  hardware signals
                                    r_TDIR <= '1';
                                    r_TOE <= '1';
                                    r_CE <= '0';
                                    r_OE <= '1';
                                    r_WE <= '1';
                                    r_LH <= '0';
                                    r_RAL_L <= '1';
                                    r_RAL_H <= '1';
                                    --  data
                                    r_data_to <= (others=>'0');                                                                        
                                    --  parto
                                    r_stage <= s_IDLE;
                            
                                when s_IDLE =>
                                    --  possono arrivare una serie di segnali:
                                    --  dal bus oppure dai registri.
                                    --  i registri che qui ho a disposizione sono i registri logici:
                                    --  ho 8 registri logici a 32 bit che contengono:
                                    --  un numero a 17 bit che identifica lo start range e poi l'incremento nei restanti 15
                                    --  se l'incremento valesse 0, si estende su tutta la memoria disponibile a partire dallo start
                                    cond := (ss_dev_chg & ss_dev_out_drdy);
                                    case (cond) is
                                        when "00" =>
                                            --  idle : aspettiamo che succeda qualcosa
                                            r_TDIR <= '1';  --  fpga to sram
                                            r_TOE <= '0';   --  transceiver active
                                            r_CE <= '0';    --  keeping the device selected
                                            r_OE <= '1';    --  sram idle
                                            r_WE <= '1';    --  sram idle
                                            r_RAL_L <= '1'; --  address latches to transparent mode
                                            r_RAL_H <= '1'; --  address latches to transparent mode
                                            r_stage <= s_IDLE;
                                        
                                        when "10" =>
                                            --  device change : lettura o scrittura su registro fisico/logico
                                            r_stage <= s_REG_0;
                                        
                                        when "01" =>
                                            bc := 0;
                                            phys_address := to_integer(unsigned(ss_dev_out_addr)) - 64;
                                            sram_address <= std_logic_vector(to_unsigned(phys_address, 17));
                                            if (ss_dev_out_cmd='0') then
                                                --  scrittura
                                                r_jump <= s_W_0;
                                            else
                                                --  lettura
                                                r_jump <= s_R_0;
                                            end if;
                                            --  going to place the address
                                            r_stage <= s_A_0;
                                        
                                        when others =>
                                            r_stage <= s_IDLE;
                                    end case;
                                
                                when s_REG_0 =>
                                    --  i registri vengono ignorati
                                    if (ss_dev_chg='0') then
                                        --  registri rilasciati
                                        r_dev_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        --  aspetto che i registri si disinneschino
                                        r_dev_in_latch <= '1';
                                        r_stage <= s_REG_0;
                                    end if;
                                                                                                                                                                    
                                --------------------------------------------------------------------------------------------
                                --
                                --  ADDRESS PLACING
                                --
                                --------------------------------------------------------------------------------------------
                                when s_A_0 =>
                                    --  posizionamento indirizzo
                                    r_TDIR <= '1';  --  fpga to sram
                                    r_TOE <= '0';   --  transceiver active
                                    r_LH <= sram_address(16);
                                    r_data_to <= sram_address((8*(bc+1))-1 downto bc*8);
                                    --  need to wait for the latch setup and hold times
                                    clockCounter := 0;
                                    r_stage <= s_A_0_l0;
                                
                                when s_A_0_l0 =>
                                    if (clockCounter=(latch_tsu-1)) then
                                        clockCounter := 0;
                                        if (bc=0) then
                                            r_RAL_L <= '0';
                                        else
                                            r_RAL_H <= '0';
                                        end if;
                                        r_stage <= s_A_0_l1;
                                    else
                                        if (bc=0) then
                                            r_RAL_L <= '1';                                            
                                        else
                                            r_RAL_L <= '0';
                                        end if;
                                        r_RAL_H <= '1';
                                        clockCounter := clockCounter + 1;
                                        r_stage <= s_A_0_l0;
                                    end if;
                                
                                when s_A_0_l1 =>
                                    if (clockCounter=(latch_th-1)) then
                                        clockCounter := 0;
                                        r_stage <= s_A_1;
                                    else
                                        clockCounter := clockCounter + 1;
                                        r_stage <= s_A_0_l1;
                                    end if;
                                                                
                                when s_A_1 =>
                                    if (bc=0) then
                                        --  posiziono secondo pezzo dell'indirizzo
                                        bc := 1;
                                        r_stage <= s_A_0;
                                    else
                                        --  posso andare sull'operazione
                                        bc := 0;
                                        r_stage <= r_jump;
                                    end if;
                                
                                --------------------------------------------------------------------------------------------
                                --
                                --  WRITE
                                --
                                --------------------------------------------------------------------------------------------
                                when s_W_0 =>
                                    --  scrittura -> posiziono il byte sul bus e preparo la scrittura
                                    r_TDIR <= '1';  --  fpga to sram
                                    r_TOE <= '0';   --  transceiver active
                                    r_data_to <= ss_dev_out_data;
                                    clockCounter := 0;
                                    r_stage <= s_W_P;
                                --
                                when s_W_P =>
                                    --  writing data
                                    if (clockCounter=5) then
                                        r_WE <= '1';
                                        clockCounter := 0;
                                        r_stage <= s_P_1;
                                    else
                                        clockCounter := clockCounter + 1;
                                        r_WE <= '0';
                                        r_stage <= s_W_P;
                                    end if;
                               
                                --------------------------------------------------------------------------------------------
                                --
                                --  READ
                                --
                                --------------------------------------------------------------------------------------------
                                when s_R_0 =>
                                    --  inizio lettura
                                    r_TDIR <= '0';  --  sram to fpga
                                    r_TOE <= '0';   --  transceiver active
                                    r_OE <= '0';    --  enabling output
                                    clockCounter := 0;
                                    r_stage <= s_R_1;
                                --
                                when s_R_1 =>
                                    if (clockCounter=5) then
                                        --  dopo 55 nanosecondi i dati compaiono
                                        r_dev_in_data <= s_data_from;
                                        clockCounter := 0;
                                        r_stage <= s_P_1;
                                     else
                                        --  aspetto
                                        clockCounter := clockCounter + 1;
                                        r_stage <= s_R_1;
                                     end if;
                                --------------------------------------------------------------------------------------------
                                --
                                --  POST COMMAND
                                --
                                --------------------------------------------------------------------------------------------
                                when s_P_1 =>
                                    r_WE <= '1';    --  idling the sram
                                    r_OE <= '1';    --  disabling sram output
                                    r_TDIR <= '1';  --  fpga to sram direction
                                    r_TOE <= '1';   --  isolating
                                    r_RAL_L <= '1'; --  resetting address low nibble
                                    r_RAL_H <= '1'; --  resetting address high nibble
                                    --  devo dare risposta sul bus dell'avvenuta scrittura/lettura, quindi
                                    if (ss_dev_out_drdy='0') then
                                        --  fatto
                                        r_dev_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        --  aspetto
                                        r_dev_in_latch <= '1';
                                        r_stage <= s_P_1;
                                    end if;
                            
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
end Behavioral;
