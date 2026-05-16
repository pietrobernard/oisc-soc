library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

--  register file
entity regs is
    generic (
        n_base: integer := 32;              --  number of base registers of 8 bit width
        n_logical: integer := 32;           --  number of logical register
        n_cfgbits: integer := 96;           --  number of bits to specify a logical register
        memfile: string := "generic.mem"    --  file holding the register descriptions
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  now, in order to read/write from a register we need
        r_cmd: in std_logic;
        r_address: in std_logic_vector(7 downto 0);
        r_data_to: in std_logic_vector(7 downto 0);
        r_data_fr: out std_logic_vector(7 downto 0);
        latch_cmd: in std_logic;
        drdy: out std_logic;
        done: out std_logic;
        --  debug port
        dbg_stage: out integer;
        dbg_addr: out integer;
        dbg_log: out std_logic
    );
end regs;

architecture Behavioral of regs is
    --  debug signal
    signal r_dbg: integer := 0;
    
    --  ram type definition in order to act as the register file
    constant ram_width : natural := 8;
    type ram_type is array (0 to n_base - 1) of std_logic_vector(ram_width - 1 downto 0);
    signal reg_file: ram_type;
  
    --  function to load up the register setup
    type cfgram_type is array (0 to n_logical) of std_logic_vector(n_cfgbits-1 downto 0);
    impure function init_ram_bin return cfgram_type is 
      file text_file : text open read_mode is memfile;
      variable text_line : line;
      variable ram_content : cfgram_type;
      variable bv : bit_vector(ram_content(0)'range);
    begin
      for i in 0 to n_logical - 1 loop
        readline(text_file, text_line);
        read(text_line, bv);
        ram_content(i) := to_stdlogicvector(bv);
      end loop;
      return ram_content;
    end function;
    
    --  word:
    --  95
    --  AAAAA_NNN_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB
    --  bit totali sono: 8 + (5+6)*8 = 8 + 88 = 96 bit -> 12 bytes
    --  questo vuol dire: il registro 16 e' un registro composto da due registri fisici: 0 e 1. 0 rappresenta il low nibble, 1 l'high nibble.
    --  allora se scrivessi in 16, avendo 2 registri, ho bisogno di due transazioni a 8 bit per caricare il registro.
    --  quando scrivo nel low, prendo il suo indice(0) e i bit da 7 a 0 per associare. Simmetricamente nel caso di una lettura.
    --  quindi ok, cosi penso di aver risolto tutto quanto.
    --
    --  i registri base vanno da 0 a 31, mentre quelli logici da 32 a 63 -> devo applicare nel caso la riduzione
     
    
    --  loading up the register configuration
    signal cfg_reg: cfgram_type := init_ram_bin;
    signal r_reg_def: std_logic_vector(n_cfgbits-1 downto 0) := (others=>'0');
    
    --  various signals to drive the interface and the register file
    signal r_data_out: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_drdy: std_logic := '0';
    signal r_done: std_logic := '0';
    
    --  sampling quantities
    signal s_address: std_logic_vector(7 downto 0) := (others=>'0');
    signal s_data_to: std_logic_vector(7 downto 0) := (others=>'0');
    signal s_latch: std_logic := '0';
    signal s_cmd: std_logic := '0';
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_PHY, s_PHY_w0, s_PHY_w1, s_PHY_r0, s_PHY_r1, s_LOG, s_LOGPRE, s_LOG_w0, s_LOG_w1, s_LOG_w2, s_LOG_r0, s_LOG_r1, s_LOG_r2);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    --  auxiliary registers
    signal preg_addr: natural := 0;
    signal bit_low: natural := 0;
    signal bit_high: natural := 0;
    
    --  synchro
    signal ss_sync_0: std_logic := '0';
begin
    --  sampler
    SAMPLER:    process (sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                s_address <= (others=>'0');
                                s_data_to <= (others=>'0');
                                s_latch <= '0';
                                s_cmd <= '0';
                                ss_sync_0 <= '0';
                            
                            when s_IDLE =>
                                s_address <= r_address;
                                s_data_to <= r_data_to;
                                s_latch <= latch_cmd;
                                s_cmd <= r_cmd;
                                ss_sync_0 <= '1';
                            
                            when s_PHY =>
                                ss_sync_0 <= '0';
                            
                            when s_LOG =>
                                ss_sync_0 <= '0';
                            
                            when s_LOGPRE =>
                                ss_sync_0 <= '0';
                            
                            when s_LOG_w1 =>
                                s_latch <= latch_cmd;
                            
                            when s_LOG_w2 =>
                                s_data_to <= r_data_to;
                                s_latch <= latch_cmd;
                                ss_sync_0 <= '1';
                            
                            when s_LOG_r1 =>
                                s_latch <= latch_cmd;
                            
                            when s_LOG_r2 =>
                                s_latch <= latch_cmd;
                                ss_sync_0 <= '1';
                        
                            when s_PHY_w1 =>
                                s_latch <= latch_cmd;
                            
                            when s_PHY_r1 =>
                                s_latch <= latch_cmd;
                        
                            --  finally
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
    --  main
    MAIN:       process (sysClk)
                    variable logical: std_logic := '0';
                    variable addr: integer := 0;
                    variable c: integer := 0;
                    variable c_lim: integer := 0;
                    --variable preg_addr: integer := 0;
                    --variable bit_low: integer := 0;
                    --variable bit_high: integer := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_data_out <= (others=>'0');
                                    r_drdy <= '0';
                                    r_done <= '0';
                                    c := 0;
                                    logical := '0';
                                    r_jump <= s_IDLE;
                                    r_stage <= s_IDLE;
                                    r_dbg <= 0;
                            
                                when s_IDLE =>
                                    r_data_out <= (others=>'0');
                                    r_dbg <= 1;
                                    if ((ss_sync_0='1') and (s_latch='1')) then
                                        --  latching a new command and setting the logical/non logical
                                        addr := to_integer(unsigned(s_address));
                                        dbg_addr <= addr;
                                        if (addr > (n_base-1)) then -- changed 31 to n_base-1
                                            addr := addr - n_base;  -- changed 32 to n_base
                                            logical := '1';
                                            r_reg_def <= cfg_reg(addr);
                                            r_stage <= s_LOG;
                                        else
                                            addr := addr;
                                            logical := '0';
                                            r_stage <= s_PHY;
                                        end if;
                                        --  jumping now
                                        dbg_log <= logical;
                                    else
                                        --  waiting here
                                        r_stage <= s_IDLE;
                                    end if;
                            
                                when s_LOG =>
                                    r_dbg <= 2;
                                    --  when an operation on a logical register is requested,
                                    c := 0;
                                    c_lim := to_integer(unsigned(r_reg_def(90 downto 88)));
                                    if (s_cmd='0') then
                                        --  gathering the extrema into which we have to loop through the configuration word for this register
                                        --  need to start a write cycle, nibble by nibble loading from the external interface according to the specifics, so:
                                        r_jump <= s_LOG_w0;
                                    else
                                        --  read command
                                        r_jump <= s_LOG_r0;
                                    end if;
                                    r_stage <= s_LOGPRE;
                            
                                when s_LOGPRE =>
                                    --  loading new indexes
                                    preg_addr <= to_integer(unsigned(r_reg_def((11*(c+1)-1) downto (11*c + 6))));
                                    bit_low <= to_integer(unsigned(r_reg_def((11*c + 5) downto (11*c + 3))));
                                    bit_high <= to_integer(unsigned(r_reg_def((11*c + 2) downto (11*c))));
                                    --  going
                                    r_stage <= r_jump;
                            
                                when s_LOG_w0 =>
                                    r_dbg <= 3;
                                    --  getting the address of the nibble-register into which we have to write first
                                    reg_file(preg_addr)(bit_high downto bit_low) <= s_data_to(bit_high downto bit_low);
                                    --  using r_drdy as temporary signal if the write is not yet complete
                                    if (c=(c_lim-1)) then
                                        --  last
                                        r_done <= '1';
                                    else
                                        r_done <= '0';
                                    end if;
                                    --r_drdy <= '1';
                                    r_stage <= s_LOG_w1;
                            
                                when s_LOG_w1 =>
                                    r_dbg <= 4;
                                    --  now to wait
                                    if (s_latch='0') then
                                        --  let's see
                                        r_drdy <= '0';
                                        r_done <= '0';
                                        if (c=(c_lim-1)) then
                                            --  done with the write op
                                            c := 0;
                                            r_stage <= s_IDLE;
                                        else
                                            --  still have more nibbles to write
                                            c := c + 1;
                                            r_stage <= s_LOG_w2;
                                        end if;
                                    else
                                        --  waiting, moved this from s_LOG_w0
                                        r_drdy <= '1';
                                        r_stage <= s_LOG_w1;
                                    end if;
                            
                                when s_LOG_w2 =>
                                    r_dbg <= 5;
                                    if ((ss_sync_0='1') and (s_latch='1')) then
                                        --  let's see
                                        r_stage <= s_LOGPRE;
                                    else
                                        --  waiting
                                        r_stage <= s_LOG_w2;
                                    end if;
                            
                                when s_LOG_r0 =>
                                    r_dbg <= 6;
                                    --  getting coordinates
--                                    preg_addr := to_integer(unsigned(r_reg_def((11*(c+1)-1) downto (11*c + 6))));
--                                    bit_low := to_integer(unsigned(r_reg_def((11*c + 5) downto (11*c + 3))));
--                                    bit_high := to_integer(unsigned(r_reg_def((11*c + 2) downto (11*c))));
                                    --  reading from memory
                                    r_data_out(bit_high downto bit_low) <= reg_file(preg_addr)(bit_high downto bit_low);
                                    --r_drdy <= '1';
                                    if (c=(c_lim-1)) then
                                        r_done <= '1';
                                    else
                                        r_done <= '0';
                                    end if;
                                    r_stage <= s_LOG_r1;
                            
                                when s_LOG_r1 =>
                                    r_dbg <= 7;
                                    if (s_latch='0') then
                                        --  checking
                                        r_drdy <= '0';
                                        r_done <= '0';
                                        if (c=(c_lim-1)) then
                                            --  done with the read operation
                                            c := 0;
                                            r_stage <= s_IDLE;
                                        else
                                            c := c+ 1;
                                            r_stage <= s_LOG_r2;
                                        end if;
                                    else
                                        --  waiting for assertion. moved the data ready from above here
                                        r_drdy <= '1';
                                        r_stage <= s_LOG_r1;
                                    end if;
                            
                                when s_LOG_r2 =>
                                    r_dbg <= 8;
                                    if ((ss_sync_0='1') and (s_latch='1')) then
                                        --  going
                                        r_stage <= s_LOGPRE;
                                    else
                                        r_stage <= s_LOG_r2;
                                    end if;
                            
                                when s_PHY =>
                                    r_dbg <= 9;
                                    --  physical address operation
                                    if (s_cmd='0') then
                                        --  write command
                                        r_stage <= s_PHY_w0;
                                    else
                                        --  read command
                                        r_stage <= s_PHY_r0;
                                    end if;
                                
                                when s_PHY_w0 =>
                                    r_dbg <= 10;
                                    --  writing
                                    reg_file(addr) <= s_data_to;
                                    --r_drdy <= '1';
                                    r_done <= '1';
                                    r_stage <= s_PHY_w1;
                                
                                when s_PHY_w1 =>
                                    r_dbg <= 11;
                                    if (s_latch='0') then
                                        r_drdy <= '0';
                                        r_done <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        --  moved this from above
                                        r_drdy <= '1';
                                        r_stage <= s_PHY_w1;
                                    end if;
                               
                                when s_PHY_r0 =>
                                    r_dbg <= 12;
                                    --  reading
                                    r_data_out <= reg_file(addr);
                                    --r_drdy <= '1';
                                    r_done <= '1';
                                    r_stage <= s_PHY_r1;
                                
                                when s_PHY_r1 =>
                                    r_dbg <= 13;
                                    if (s_latch='0') then
                                        r_drdy <= '0';
                                        r_done <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        --  moved this from above
                                        r_drdy <= '1';
                                        r_stage <= s_PHY_r1;
                                    end if;
                            
                                --  finally
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
    --  assignment
    r_data_fr <= r_data_out;
    drdy <= r_drdy;
    done <= r_done;
    dbg_stage <= r_dbg;
end Behavioral;
--  inizio indici registri: 6,10 | 17,21 | 28,32 | 39,43 ...
--  quindi: 6, 6+11, 17+11, 28+11, ecc
--  10 downto 6
--  17 downto 11 => (11*(c+1) - 1) downto (11*c + 6)
--  quindi per c = 0 : 10 downto 6
--  quindi per c = 1 : 21 downto 17
--  quindi per c = 2 : 32 downto 28
--
--  poi invece il bit low e il bit high:
--  bit low: 3,5 | 14,16 | 25,27
--  5 downto 3
--  16 downto 14
--  27 downto 25
--  -> (11*c + 5) downto (11*c + 3)
--  c = 0: 5 downto 3
--  c = 1: 16 downto 14
--  c = 2: 27 downto 25
--
--  per il bit high
--  2 downto 0
--  13 downto 11
--  24 downto 22
--  -> (11*c + 2) downto (11*c)
--  c = 0: 2 downto 0
--  c = 1: 13 downto 11
--  c = 2: 24 downto 22


--  99999_988_88888_888_777_77777_776_666_66666_655_555_55555_444_444_44433_333_333_33222_222_222_21111_111_111_10000_000_000
--  54321_098_76543_210_987_65432_109_876_54321_098_765_43210_987_654_32109_876_543_21098_765_432_10987_654_321_09876_543_210
--  AAAAA_NNN_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB_RRRRR_BBB_BBB

