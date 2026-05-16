library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  virtual registers for the keyboard
--  0:  keypress flag scan0
--  1:  keybreak flag scan0
--  2:  keypress flag scan1
--  3:  keybreak flag scan1
--  4:  scancode 0
--  5:  scancode 1

--  nel protocollo PS/2 quando si premono piu tasti, succede questo:
--  il tasto premuto per primo invia il suo MAKE code, a quel punto, la tastiera invia il makecode del secondo premuto, senza il break del primo.
--  questo indica la pressione simultanea dei tasti.
--
--  per la tastiera quindi il detect si compone di queste fasi:
--  prendo lo scan code : questo e' quello che fa fede.
--  prima di procedere devo capire i codici successivi:
--  se il successivo e' di nuovo uguale al precedente, significa che sono in keypress
--  se il successivo fosse il break, significa che ho fatto il keyrelease
--  attendo poi il codice del tasto per confermare.


entity subdev_GPIO_kbd_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  hardware id for the UART
        --  this allows for data-packets sent from the uart device to reach this and not other sub-devs of the uart
        hw_id: integer := 0;
        --  device manager setup
        dev_id: integer := 1;
        local_mem_begin: integer := 0;      --  start of memory space
        local_mem_nvrt: integer := 0;       --  number of virtual registers
        sram_mem_begin: integer := 0;       --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;         --  end of sram range
        regcfg: string := "generic.mem";    --  logical registers configuration file
        t_bef_sample: natural := 32_000      --  clock cycles to wait before sampling and resetting the ic
         
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  sub-system signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  booking system
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;          --  this line will go high if the system bus has been granted
        bus_err_sys: in std_logic;
        --  hardware lines
        extport: inout std_logic_vector(data_width-1 downto 0);
        strobe_S: in std_logic;
        strobe_M: out std_logic--;
        --  debug lines
        --dbg_0: out std_logic_vector(7 downto 0);
        --dbg_1: out std_logic_vector(7 downto 0);
        --dbg_signal_strobe_S: out std_logic;
        --dbg_signal_strobe_M: out std_logic
    );
end subdev_GPIO_kbd_v2;

architecture Behavioral of subdev_GPIO_kbd_v2 is    
    --  subdev interface
    signal r_bus_in_cmd: std_logic := '0';
    signal r_bus_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_in_keep: std_logic := '0';
    signal r_bus_in_latch: std_logic := '0';
    
    --  sampling sub-bus
    signal s_bus_out_cmd: std_logic;
    signal s_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_bus_out_drdy: std_logic;
    signal s_bus_out_done: std_logic;
    signal s_bus_err: std_logic;
    signal s_bus_chg: std_logic;
    
    --  sampling signals for the bus interface
    signal ss_bus_out_drdy: std_logic;
    signal ss_bus_out_done: std_logic;
    signal ss_bus_err: std_logic;
    signal ss_bus_chg: std_logic;
    signal ss_bus_out_cmd: std_logic;
    signal ss_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_bus_out_data: std_logic_vector(data_width-1 downto 0);
            
    --  control signals for the hardware port    
    signal r_data_to_port: std_logic_vector(data_width-1 downto 0);
    signal s_data_from_port: std_logic_vector(data_width-1 downto 0);
    signal r_port_dir: std_logic_vector(data_width-1 downto 0);
    signal r_data_dir: std_logic_vector(data_width-1 downto 0);
        
    --  strobing
    signal r_strobe_M: std_logic := '0';
    
    --  state machine for port
    type t_SM is (s_INIT, s_PRE, s_IDLE, s0, s1, s2, s3, s4, s5);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_IDLE;
    signal r_jump_end: t_SM := s_IDLE;
    
    --  state machine for main
    type t_SM_m is (s_INIT_m, s_IDLE_m, s_REG_m, s_VRT_0_m, s_VRT_1_m, s_VRT_2_m);
    signal r_stage_m: t_SM_m := s_INIT_m;
    
    --  buffer to hold in the key scans
    type codes is array (0 to 2 ) of std_logic_vector (7 downto 0);
    signal kbd_scancodes: codes := (x"00", x"00", x"00");
    
    --  registers that hold the values
    signal r_new_0: std_logic;
    signal r_new_1: std_logic;
    signal r_data_0: std_logic_vector(7 downto 0);
    signal r_data_1: std_logic_vector(7 downto 0);
    
    --  segnali di sync
    signal portEvent: std_logic := '0';
    signal portHandled: std_logic := '0';
    
    --  segnali per la pora
    signal strobe_S_sync: std_logic;
    signal ss_strobe_S: std_logic;
    signal data_from_port_sync: std_logic_vector(7 downto 0);
    signal ss_data_from_port: std_logic_vector(7 downto 0);
    --signal sig: std_logic := '0';
    
    --  synchronizer
    signal ss_sync_0: std_logic := '0';
    signal ss_sync_1: std_logic := '0';
begin
    --  subbus
    SBUSINT:    entity work.subbus_dev_v2(Behavioral)
                generic map (
                    dev_id => dev_id,
                    local_mem_begin => local_mem_begin,
                    local_mem_nvrt => local_mem_nvrt,
                    regcfg => regcfg
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_done_S => bus_done_S,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
                    bus_err_sys => bus_err_sys,
                    --  interface signals
                    dev_in_cmd => r_bus_in_cmd,
                    dev_in_addr => r_bus_in_addr,
                    dev_in_data => r_bus_in_data,
                    dev_in_keep => r_bus_in_keep,
                    dev_in_latch => r_bus_in_latch,
                    dev_out_cmd => s_bus_out_cmd,   --  output command
                    dev_out_addr => s_bus_out_addr, --  output address
                    dev_out_data => s_bus_out_data, --  output data
                    dev_out_drdy => s_bus_out_drdy, --  when new data arrives
                    dev_out_done => s_bus_out_done, --  when no more transactions
                    dev_err => s_bus_err,           --  if an error occurrs
                    dev_chg => s_bus_chg            --  when an operation on local physical registers completes
                );

    --  hardware driver for the ports
    genloop_PORTS: for i in 0 to 7 generate
        PORTDRV_i: entity work.inout_port(Behavioral) generic map (nbits => 1) port map (io(0) => extport(i), data_to(0) => r_data_to_port(i), data_from(0) => s_data_from_port(i), dir=>r_port_dir(i));
    end generate genloop_PORTS;
    
    --  sampler
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage_m) is
                            when s_INIT_m =>
                                ss_bus_out_drdy <= '0';
                                ss_bus_out_done <= '0';
                                ss_bus_chg <= '0';
                                ss_bus_err <= '0';
                        
                            when s_IDLE_m =>
                                ss_bus_out_cmd <= s_bus_out_cmd;
                                ss_bus_out_addr <= s_bus_out_addr;
                                ss_bus_out_data <= s_bus_out_data;
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_chg <= s_bus_chg;
                            
                            when s_REG_m =>
                                ss_bus_chg <= s_bus_chg;
                            
                            when s_VRT_1_m =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
    
    --  main driver
    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                    variable addr: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage_m <= s_INIT_m;
                        else
                            case (r_stage_m) is
                                when s_INIT_m =>                                    
                                    --  initializing bus controls
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_addr <= (others=>'0');
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_keep <= '0';
                                    r_bus_in_latch <= '0';
                                    --  initializing port sync signals
                                    portHandled <= '0';
                                    --  going                                    
                                    r_stage_m <= s_IDLE_m;
                                
                                when s_IDLE_m =>
                                    --  qui dobbiamo attendere i vari eventi: registri, virtuale e la porta hardware
                                    cond := (ss_bus_out_drdy & ss_bus_chg);
                                    case (cond) is
                                        when "01" =>
                                            --  evento registri
                                            r_stage_m <= s_REG_m;
                                        
                                        when "10" =>
                                            --  evento virtuale
                                            r_stage_m <= s_VRT_0_m;
                                                                                                                       
                                        when others =>
                                            r_stage_m <= s_IDLE_m;
                                    end case;                                                           
                                
                                --  si rilasciano i registri locali
                                when s_REG_m =>
                                    if (ss_bus_chg='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage_m <= s_IDLE_m;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage_m <= s_REG_m;
                                    end if;
                            
                                --  si controlla l'operazione richiesta
                                when s_VRT_0_m =>
                                    if (ss_bus_out_cmd='1') then
                                        --  only read is allowed from the keyboard
                                        addr := to_integer(unsigned(ss_bus_out_addr)) - 64;
                                        case (addr) is
                                            when 0 =>
                                                --  indirizzo virtuale 0 : flag scancode 0 + flag scancode 1
                                                r_bus_in_data(7 downto 2) <= (others=>'0');
                                                if (portEvent='1') then
                                                    r_bus_in_data(1 downto 0) <= (r_new_1 & r_new_0);
                                                else
                                                    r_bus_in_data(1 downto 0) <= "00";
                                                end if;
                                                r_stage_m <= s_VRT_1_m;
                                            
                                            when 1 =>
                                                --  indirizzo virtuale 1 : scancode 0
                                                r_bus_in_data <= r_data_0;
                                                r_stage_m <= s_VRT_2_m;
                                            
                                            when 2 =>
                                                --  indirizzo virtuale 2 : scancode 1
                                                r_bus_in_data <= r_data_1;
                                                r_stage_m <= s_VRT_2_m;
                                            
                                            when others =>
                                                r_bus_in_data <= x"ff";
                                                r_stage_m <= s_VRT_1_m;
                                        end case;
                                    else
                                        --  invalid command, so
                                        r_stage_m <= s_VRT_1_m;
                                    end if;
                            
                                --  rilascio del bus di sistema
                                when s_VRT_1_m =>
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage_m <= s_IDLE_m;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage_m <= s_VRT_1_m;
                                    end if;
                            
                                --  rilascio il controller della tastiera
                                --  questo meccanismo di interlock e' abbastanza superfluo perche' la tastiera in realta'
                                --  e' molto piu' lenta del resto del sistema (15 kHz contro 100 MHz) quindi l'intera operazione
                                --  di lettura e reset delle flag comporta pochi cicli di clock rispetto a quelli richiesti per
                                --  reagire alla pressione di un tasto.
                                when s_VRT_2_m =>
                                    if (portEvent='0') then
                                        portHandled <= '0';
                                        r_stage_m <= s_VRT_1_m;
                                    else
                                        portHandled <= '1';
                                        r_stage_m <= s_VRT_2_m;
                                    end if;
                                
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
    --  port hardware driver
    SAMPDRV:    process(sysClk)
                
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s_PRE =>
                                strobe_S_sync <= strobe_S;
                                ss_strobe_S <= strobe_S_sync;
                                ss_sync_0 <= '1';
                            
                            when s_IDLE =>
                                strobe_S_sync <= strobe_S;
                                ss_strobe_S <= strobe_S_sync;
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s0 =>
                                ss_data_from_port <= s_data_from_port;
                                ss_sync_0 <= '1';
                            
                            when s1 =>
                                strobe_S_sync <= strobe_S;
                                ss_strobe_S <= strobe_S_sync;
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s2 =>
                                data_from_port_sync <= s_data_from_port;
                                ss_data_from_port <= data_from_port_sync;
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '1';
                            
                            when s3 =>
                                data_from_port_sync <= s_data_from_port;
                                ss_data_from_port <= data_from_port_sync;
                                ss_sync_0 <= '1';
                                                            
                            when s4 =>
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when others =>
                                null;
                            
                        end case;
                    end if;
                end process SAMPDRV;
    
    PORTDRV:    process(sysClk)
                    variable c: natural := 0;
                    variable ncn: natural := 0;
                    variable sw: natural := 0;
                    variable cond: std_logic_vector(1 downto 0) := "00";
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else                        
                            case (r_stage) is
                                when s_INIT =>
                                    --  hardware port
                                    r_data_to_port <= (others=>'0');
                                    r_port_dir <= (others=>'0');
                                    r_data_dir <= (others=>'0');
                                    --  master strobe
                                    c := 0;
                                    ncn := 0;
                                    r_data_0 <= (others=>'0');
                                    r_data_1 <= (others=>'0');
                                    kbd_scancodes(0) <= (others=>'0');
                                    kbd_scancodes(1) <= (others=>'0');
                                    r_jump <= s2;
                                    --  starting
                                    r_stage <= s_PRE;
                                
                                when s_PRE =>
                                    if ((ss_sync_0='1') and (ss_strobe_S='0')) then
                                        r_strobe_M <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_strobe_M <= '1';
                                        r_stage <= s_PRE;
                                    end if;
                                                                                               
                                when s_IDLE =>
                                    if (portEvent='1') then
                                        --  se la flag di portEvent e' alta, io devo restare in lock fintanto che non faccio il clear                                        
                                        --  ignoro quindi la porta
                                        if (portHandled='1') then
                                            r_stage <= s5;
                                        else
                                            r_stage <= s_IDLE;
                                        end if;
                                    else
                                        --  se non c'e' flag, posso controllare gli eventi sulla porta
                                        if (ss_strobe_S='1') then
                                            r_stage <= s0;
                                        else
                                            r_stage <= s_IDLE;
                                        end if;
                                    end if;
                                
                                --  ora dobbiamo aspettare questo intervallo di tempo perche' la fpga e' molto piu' veloce
                                --  della tastiera e anche se i dati sono disponibili, se azzerassimo troppo rapidamente la flag di nuovi dati,
                                --  l'interfaccia con la tastiera si sblocca e inizierebbe a ricampionare i dati in arrivo che potrebbero essere
                                --  gli ultimi impulsi di clock del codice precedente. Un ciclo di clock della tastiera equivale a 8000 cicli di clock della fpga
                                --  attendo 4 cicli di clock della tastiera, cioe' 32000 cicli di fpga ovvero 320 microsecondi prima di continuare.
                                when s0 =>
                                    case (ss_sync_0) is
                                        when '1' =>
                                            if (c=(t_bef_sample-1)) then
                                                c := 0;
                                                --  check scan codes compositi
                                                if (ss_data_from_port="11100000") then
                                                    --  cancello via questo
                                                    --sig <= '1';
                                                    r_stage <= s1;
                                                else
                                                    r_stage <= r_jump;
                                                end if;
                                            else
                                                c := c + 1;
                                                r_stage <= s0;
                                            end if;
                                        
                                        when others =>
                                            --  waiting
                                            r_stage <= s0;
                                    end case;
                                
                                --  in s1 si azzera la flag di DRDY del controller della tastiera
                                when s1 =>
                                    if (ss_strobe_S='0') then
                                        r_strobe_M <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_strobe_M <= '1';
                                        r_stage <= s1;
                                    end if;
                                
                                --  in s2 si verifica la situazione
                                when s2 =>
                                    if (ss_sync_1='1') then
                                        case (ncn) is
                                            when 0 =>
                                                --  primo scancode
                                                kbd_scancodes(0) <= ss_data_from_port;
                                                ncn := 1;
                                                sw := 0;
                                                r_jump <= s2;
                                                r_stage <= s1;
                                            
                                            when 1 =>
                                                --  secondo scancode, quindi
                                                if (((ss_data_from_port=kbd_scancodes(0)) and (sw=0)) or ((ss_data_from_port=kbd_scancodes(1)) and (sw=1))) then
                                                    --  ripetizione del primo scancode
                                                    ncn := 1;
                                                    r_jump <= s2;
                                                    r_stage <= s1;
                                                else
                                                    if (ss_data_from_port="11110000") then
                                                        --  break di uno scancode
                                                        r_jump <= s3;
                                                        r_stage <= s1;
                                                    else
                                                        --  nuovo scancode
                                                        if (sw=0) then
                                                            kbd_scancodes(1) <= ss_data_from_port;
                                                        else
                                                            kbd_scancodes(0) <= ss_data_from_port;
                                                        end if;
                                                        ncn := 2;
                                                        r_jump <= s2;
                                                        r_stage <= s1;
                                                    end if;
                                                end if;
                                        
                                            when 2 =>
                                                --  terzo scancode, quindi
                                                if (((ss_data_from_port=kbd_scancodes(1)) and (sw=0)) or ((ss_data_from_port=kbd_scancodes(0)) and (sw=1))) then
                                                    --  ripetizione secondo scancode
                                                    ncn := 2;
                                                    r_jump <= s2;
                                                    r_stage <= s1;
                                                else
                                                    if (ss_data_from_port="11110000") then
                                                        --  break di uno scancode
                                                        r_jump <= s3;
                                                        r_stage <= s1;
                                                    else
                                                        --  non posso avere altri scancodes
                                                        ncn := 0;
                                                        sw := 0;
                                                        r_new_0 <= '0';
                                                        r_new_1 <= '0';
                                                        r_stage <= s4;
                                                    end if;
                                                end if;
                                        
                                            when others =>
                                                r_jump <= s2;
                                                r_stage <= s1;
                                                    
                                        end case;
                                    else
                                        --  waiting
                                        r_stage <= s2;
                                    end if;
                                
                                --  qui devo gestire i BREAK
                                when s3 =>
                                    if (ss_sync_0='1') then
                                        case (ncn) is
                                            when 1 =>
                                                if (((ss_data_from_port=kbd_scancodes(0)) and (sw=0)) or ((ss_data_from_port=kbd_scancodes(1)) and (sw=1))) then
                                                    --  rilascio del primo e unico pulsante premuto
                                                    if (sw=1) then
                                                        r_new_1 <= '1';
                                                        r_data_1 <= kbd_scancodes(1);
                                                    else
                                                        r_new_0 <= '1';
                                                        r_data_0 <= kbd_scancodes(0);
                                                    end if;
                                                    portEvent <= '1';
                                                    sw := 0;
                                                    ncn := 0;
                                                    r_jump <= s2;
                                                    r_stage <= s1;
                                                else
                                                    --  errore
                                                    portEvent <= '0';
                                                    ncn := 0;
                                                    sw := 0;
                                                    r_new_0 <= '0';
                                                    r_new_1 <= '0';
                                                    r_stage <= s4;
                                                end if;
                                            
                                            when 2 =>
                                                if (((ss_data_from_port=kbd_scancodes(1)) and (sw=0)) or ((ss_data_from_port=kbd_scancodes(0)) and (sw=1))) then
                                                    --  rilascio dell'ultimo premuto
                                                    if (sw=0) then
                                                        r_new_1 <= '1';
                                                        r_data_1 <= kbd_scancodes(1);
                                                    else
                                                        r_new_0 <= '1';
                                                        r_data_0 <= kbd_scancodes(0);
                                                    end if;
                                                    ncn := 1;
                                                    r_jump <= s2;
                                                    r_stage <= s1;
                                                else
                                                    if (((ss_data_from_port=kbd_scancodes(0)) and (sw=0)) or ((ss_data_from_port=kbd_scancodes(1)) and (sw=1))) then
                                                        --  rilascio del primo premuto
                                                        if (sw=0) then
                                                            r_new_0 <= '1';
                                                            r_data_0 <= kbd_scancodes(0);
                                                            sw := 1;
                                                        else
                                                            r_new_1 <= '1';
                                                            r_data_1 <= kbd_scancodes(1);
                                                            sw := 0;
                                                        end if;
                                                        ncn :=  1;
                                                        r_jump <= s2;
                                                        r_stage <= s1;
                                                    else
                                                        --  errore
                                                        portEvent <= '0';
                                                        ncn := 0;
                                                        sw := 0;
                                                        r_new_0 <= '0';
                                                        r_new_1 <= '0';
                                                        r_stage <= s4;
                                                    end if;
                                                end if;
                                            
                                            when others =>
                                                r_jump <= s2;
                                                r_stage <= s1;
                                                    
                                        end case;
                                    else
                                        --  waiting
                                        r_stage <= s3;
                                    end if;
                            
                                when s4 =>
                                    if (c=(400_000-1)) then
                                        portEvent <= '0';
                                        c := 0;
                                        sw := 0;
                                        r_jump <= s2;
                                        r_stage <= s1;
                                    else
                                        c:= c + 1;
                                        r_stage <= s4;
                                    end if;
                            
                                when s5 =>
                                    if (portHandled='0') then
                                        --  a questo punto, facciamo il clear di eventuali residui presenti sulla porta
                                        r_stage <= s4;
                                    else
                                        portEvent <= '0';
                                        r_new_0 <= '0';
                                        r_new_1 <= '0';
                                        r_stage <= s5;
                                    end if;
                                
                            end case;
                        end if;
                    end if;
                end process PORTDRV;
                
    --  hardware drivers
    strobe_M <= r_strobe_M;
    
    --  debug
    --dbg_0 <= r_data_0;
    --dbg_1 <= r_data_1;
    --dbg_signal_strobe_S <= sig;
    --dbg_signal_strobe_M <= '0';
    
end Behavioral;
