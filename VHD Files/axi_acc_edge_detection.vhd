library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library xil_defaultlib;
use xil_defaultlib.definitions_PK.all;

entity axi_acc_edge_detection is
    Generic (
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 5;
        G_DATA_WIDTH       : natural := DATA_WIDTH;
        G_REG_WIDTH        : natural := REG_WIDTH;
        G_MAX_BUFF_LENGTH  : natural := MAX_BUFF_LENGTH
    );
    Port (
        clk   : in std_logic;
        reset : in std_logic;
        
        --------------------------- AXI4-Lite interface ---------------------------
        --  AXI4-Lite Write address channel
        s_axi_lite_awaddr  : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        -- protection type (privilege and security of transaction)
        s_axi_lite_awprot  : in std_logic_vector(2 downto 0);
        s_axi_lite_awvalid : in std_logic;
        s_axi_lite_awready : out std_logic;
        
        --  AXI4-Lite Write data channel
        s_axi_lite_wdata  : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_lite_wstrb  : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_lite_wvalid : in std_logic;
        s_axi_lite_wready : out std_logic;
        
        --  AXI4-Lite Write response channel
        s_axi_lite_bresp  : out std_logic_vector(1 downto 0);
        s_axi_lite_bvalid : out std_logic;
        s_axi_lite_bready : in std_logic;
        
        --  AXI4-Lite Read address related signals
        s_axi_lite_araddr  : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        -- protection type (privilege and security of transaction)
        s_axi_lite_arprot  : in std_logic_vector(2 downto 0);
        s_axi_lite_arvalid : in std_logic;
        s_axi_lite_arready : out std_logic;
        
        --  AXI4-Lite Read data related signals
        s_axi_lite_rdata  : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_lite_rvalid : out std_logic;
        s_axi_lite_rready : in std_logic;
        s_axi_lite_rresp  : out std_logic_vector(1 downto 0);
        
        --------------------------- AXI Stream interface ---------------------------
        -- Input AXI Stream interface
        s_axis_tdata  : in std_logic_vector(G_DATA_WIDTH-1 downto 0);
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in std_logic;
        
        -- Output AXI Stream interface
        m_axis_tdata  : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in std_logic;
        m_axis_tlast  : out std_logic 
    );
end entity axi_acc_edge_detection;

architecture rtl of axi_acc_edge_detection is
    --------------------------- AXI4-Lite signals ---------------------------
    -- AXI4-Lite register addresses
    constant REG_CTRL_ADDR     : std_logic_vector(2 downto 0) := "000";
    constant REG_EDGE_THR_ADDR : std_logic_vector(2 downto 0) := "001";
    constant REG_IMG_W_ADDR    : std_logic_vector(2 downto 0) := "010";
    constant REG_IMG_H_ADDR    : std_logic_vector(2 downto 0) := "011";
    -- When addressing 32-bit registers, 2 LSB of address are not used
    -- since each register occupies 4 byte addresses.
    constant ADDR_LSB   : natural := (C_S_AXI_DATA_WIDTH/32) + 1;
    
    -- Internal registers accessed via AXI4-Lite interface
    signal reg_ctrl     : std_logic_vector(G_REG_WIDTH-1 downto 0);
	signal reg_edge_thr : std_logic_vector(G_REG_WIDTH-1 downto 0);
	signal reg_img_w    : std_logic_vector(G_REG_WIDTH-1 downto 0);
	signal reg_img_h    : std_logic_vector(G_REG_WIDTH-1 downto 0);
	
    -- AXI4-Lite internal signals
    signal axi_awready : std_logic;
    signal axi_wready  : std_logic;
    signal axi_awaddr  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    
    signal axi_bvalid  : std_logic;
    
    signal axi_arready : std_logic;
    signal axi_rvalid  : std_logic;
    signal axi_araddr  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);

    signal reg_waddr : std_logic_vector(C_S_AXI_ADDR_WIDTH-ADDR_LSB-1 downto 0);
    signal reg_raddr : std_logic_vector(C_S_AXI_ADDR_WIDTH-ADDR_LSB-1 downto 0);
    
    signal axi_write_ready : std_logic;
    signal axi_read_ready  : std_logic;
    
    -- AXI4-Lite state machines
    type fsm_read_state_type  is (ReadAddress,  ReadData);
    type fsm_write_state_type is (WriteAddress, WriteData, WriteStalled);
    
    signal fsm_axi_read_state  : fsm_read_state_type;
    signal fsm_axi_write_state : fsm_write_state_type;
    
    ------------------------------------------------------------------------
    --------------------------- Internal signals ---------------------------
    -- Signals for acc_edge_detection component
    signal acc_enable       : std_logic;
    signal acc_reset        : std_logic;
    signal acc_data_in      : std_logic_vector(G_DATA_WIDTH-1 downto 0);
    signal acc_data_out     : std_logic_vector(G_DATA_WIDTH-1 downto 0);
    
    -- Signals for data synchronization
    signal data_in_loss : std_logic;
    signal mode_inc     : integer;
    
    signal cnt      : natural;
    signal cnt_cmp1 : natural;
    signal cnt_cmp2 : natural;
    signal cnt_cmp3 : natural;
    
    -- Buffers
    signal s_axis_tdata_buff  : std_logic_vector(G_DATA_WIDTH-1 downto 0);
    signal s_axis_tvalid_buff : std_logic;
    signal s_axis_tlast_buff  : std_logic;
    signal m_axis_tready_buff : std_logic;
    
    signal reg_edge_thr_buff : std_logic_vector(G_REG_WIDTH-1 downto 0);
    signal reg_ctrl_buff     : std_logic_vector(G_REG_WIDTH-1 downto 0);
    signal reg_img_w_buff    : std_logic_vector(G_REG_WIDTH-1 downto 0);
    signal reg_img_h_buff    : std_logic_vector(G_REG_WIDTH-1 downto 0);
    
    -- State machine
    type State_t is  (stIdle, stRx, stRxTx, stTx);
    signal curr_state, next_state : State_t;
    
    -- Debug
    attribute mark_debug : string;
    attribute mark_debug of reg_ctrl     : signal is "true";
    attribute mark_debug of reg_edge_thr : signal is "true";
    attribute mark_debug of reg_img_w    : signal is "true";
    attribute mark_debug of reg_img_h    : signal is "true";
    attribute mark_debug of acc_enable   : signal is "true";
    attribute mark_debug of acc_reset    : signal is "true";
    attribute mark_debug of acc_data_in  : signal is "true";
    attribute mark_debug of acc_data_out : signal is "true";
    attribute mark_debug of data_in_loss : signal is "true";
    attribute mark_debug of curr_state   : signal is "true";
    attribute mark_debug of next_state   : signal is "true";
    attribute mark_debug of cnt          : signal is "true";
begin
    ------------------------------------------------ AXI4-Lite ------------------------------------------------
    -- AXI4-Lite write registers
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                reg_ctrl <= std_logic_vector(to_unsigned(0,  reg_ctrl'length));
                reg_edge_thr <= std_logic_vector(to_unsigned(65,  reg_edge_thr'length));
                reg_img_w  <= std_logic_vector(to_unsigned(128, reg_img_w'length));
                reg_img_h  <= std_logic_vector(to_unsigned(128, reg_img_h'length));
            else
                if (axi_write_ready = '1') then
                    if (s_axi_lite_wstrb(0) = '1') then
                        case (reg_waddr) is
                            when REG_CTRL_ADDR => reg_ctrl(7 downto 0) <= s_axi_lite_wdata(7 downto 0);
                            when REG_EDGE_THR_ADDR => reg_edge_thr(7 downto 0) <= s_axi_lite_wdata(7 downto 0);
                            when REG_IMG_W_ADDR  =>  reg_img_w(7 downto 0) <= s_axi_lite_wdata(7 downto 0);
                            when REG_IMG_H_ADDR  =>  reg_img_h(7 downto 0) <= s_axi_lite_wdata(7 downto 0);
                            when others =>    
                        end case;
                    end if;
                    
                    if (s_axi_lite_wstrb(1) = '1') then
                        case (reg_waddr) is
                            when REG_CTRL_ADDR => reg_ctrl(15 downto 8) <= s_axi_lite_wdata(15 downto 8);
                            when REG_EDGE_THR_ADDR => reg_edge_thr(15 downto 8) <= s_axi_lite_wdata(15 downto 8);
                            when REG_IMG_W_ADDR  =>  reg_img_w(15 downto 8) <= s_axi_lite_wdata(15 downto 8);
                            when REG_IMG_H_ADDR  =>  reg_img_h(15 downto 8) <= s_axi_lite_wdata(15 downto 8);
                            when others =>    
                        end case;
                    end if;                    
                end if;
            end if;
        end if;
    end process;
    
    -- AXI4-Lite read registers
    s_axi_lite_rdata(15 downto 0) <= reg_ctrl when (reg_raddr = REG_CTRL_ADDR) else
                                     reg_edge_thr when (reg_raddr = REG_EDGE_THR_ADDR) else
                                     reg_img_w  when (reg_raddr = REG_IMG_W_ADDR ) else
                                     reg_img_h  when (reg_raddr = REG_IMG_H_ADDR ) else
                                     
                                     (others => '0');
    s_axi_lite_rdata(C_S_AXI_DATA_WIDTH-1 downto 16) <= (others => '0');                          
    
    -- Set default value of read and write response to OKAY
    s_axi_lite_bresp <= "00";
    s_axi_lite_rresp <= "00";

    -- AXI4-Lite read state machine
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                axi_arready <= '0';
                axi_rvalid  <= '0';
                fsm_axi_read_state <= ReadAddress;
            else
                case (fsm_axi_read_state) is
                    when ReadAddress =>
                        axi_arready <= '1';
                        if (axi_arready = '1' and s_axi_lite_arvalid = '1') then
                            axi_araddr <= s_axi_lite_araddr;
                            axi_arready <= '0';
                            axi_rvalid <= '1';
                            fsm_axi_read_state <= ReadData;
                        end if;
                    when ReadData =>
                        
                        if (s_axi_lite_rready = '1' and axi_rvalid = '1') then
                            axi_rvalid <= '0';
                            axi_arready <= '1';
                            fsm_axi_read_state <= ReadAddress;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    s_axi_lite_arready <= axi_arready;
    s_axi_lite_rvalid <= axi_rvalid;
    
    reg_raddr <= s_axi_lite_araddr(C_S_AXI_ADDR_WIDTH-1 downto ADDR_LSB) when (s_axi_lite_arvalid = '1') else
                        axi_araddr(C_S_AXI_ADDR_WIDTH-1 downto ADDR_LSB);
    
    -- AXI4-Lite write state machine
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                axi_awready <= '0';
                axi_wready  <= '0';
                axi_bvalid  <= '0';
                fsm_axi_write_state <= WriteAddress;
            else
                case (fsm_axi_write_state) is                                              
                    when WriteAddress =>
                        axi_awready <= '1';
                        axi_wready <= '1';
                    
                        if (axi_awready = '1' and s_axi_lite_awvalid = '1') then
                            axi_awaddr <= s_axi_lite_awaddr;
                            if (axi_wready = '1' and s_axi_lite_wvalid = '1') then
                                axi_bvalid <= '1';
                                if (s_axi_lite_bready = '0') then
                                    axi_awready <= '0';
                                    axi_wready <= '0';
                                    fsm_axi_write_state <= WriteStalled;
                                end if;
                            else
                                axi_awready <= '0';
                                fsm_axi_write_state <= WriteData;
                                if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                                    axi_bvalid <= '0';
                                end if;
                            end if;
                        else
                            if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                                axi_bvalid <= '0';
                            end if;
                        end if;
                        
                    when WriteData =>
                        if (axi_wready = '1' and s_axi_lite_wvalid = '1') then
                            axi_bvalid <= '1';
                            if (s_axi_lite_bready = '0') then
                                axi_awready <= '0';
                                axi_wready <= '0';
                                fsm_axi_write_state <= WriteStalled;
                            else
                                axi_awready <= '1';
                                axi_wready <= '1';
                                fsm_axi_write_state <= WriteAddress;
                            end if;
                        else
                            if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                                axi_bvalid <= '0';
                            end if;
                        end if;
                        
                    when WriteStalled =>
                        if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                            axi_bvalid <= '0';
                            axi_awready <= '1';
                            axi_wready <= '1';
                            fsm_axi_write_state <= WriteAddress;
                        end if;
                        
                    when others =>
                        axi_awready <= '0';
                        axi_wready <= '0';
                        axi_bvalid <= '0';
                        fsm_axi_write_state <= WriteAddress;
                end case;
            end if;
        end if;
    end process;
        
    s_axi_lite_awready <= axi_awready;
    s_axi_lite_wready  <= axi_wready;
    s_axi_lite_bvalid <= axi_bvalid;
    
    axi_write_ready <= '1' when ((fsm_axi_write_state = WriteAddress and s_axi_lite_awvalid = '1' and s_axi_lite_wvalid = '1') or
                                 (fsm_axi_write_state = WriteData and s_axi_lite_wvalid = '1')) else '0';
    
    reg_waddr <= s_axi_lite_awaddr(C_S_AXI_ADDR_WIDTH-1 downto ADDR_LSB) when (s_axi_lite_awvalid = '1') else axi_awaddr(C_S_AXI_ADDR_WIDTH-1 downto ADDR_LSB);

    ---------------------------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------ AXI_ACC_EDGE_DETECTION Implementation ------------------------------------------------
    
    -- Instance of the acc_edge_detection component
    ACC_EDGE_DETECTION : entity work.acc_edge_detection(rtl)
    generic map (
        G_DATA_WIDTH      => G_DATA_WIDTH,
        G_MAX_BUFF_LENGTH => G_MAX_BUFF_LENGTH,
        G_REG_WIDTH       => G_REG_WIDTH
    )
    port map (
        clk    => clk,
        reset  => acc_reset,
        enable => acc_enable,
        
        img_w    => reg_img_w_buff,
        img_h    => reg_img_h_buff,
        mode     => reg_ctrl_buff(1 downto 0),
        edge_thr => reg_edge_thr_buff(7 downto 0),
        border   => reg_ctrl_buff(3),
        bypass   => reg_ctrl_buff(2),
        
        data_in  => acc_data_in,
        data_out => acc_data_out
    );

    -- Changing register values (parameters) only in IDLE state
    REG_BUFF_PROC: process (clk) is
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                reg_edge_thr_buff <= (others => '0');
                reg_ctrl_buff     <= (others => '0');
                reg_img_w_buff    <= (others => '0');
                reg_img_h_buff    <= (others => '0');
            elsif (curr_state = stIdle) then
                reg_edge_thr_buff <= reg_edge_thr;
                reg_ctrl_buff     <= reg_ctrl;
                reg_img_w_buff    <= reg_img_w;
                reg_img_h_buff    <= reg_img_h;
            end if;
        end if;
    end process REG_BUFF_PROC;
    
    -- Increment for processing time depending on the mode
    MODE_INC_PROC: process (reg_ctrl_buff, reg_img_w_buff) is
    begin
        case reg_ctrl_buff(2) is
            when '0' =>
                case reg_ctrl_buff(1 downto 0) is
                    when "00" =>
                        mode_inc <= 4;
                    when "01" =>
                        mode_inc <= 2;
                    when "10" =>
                        mode_inc <= 2;
                    when "11" =>
                        mode_inc <= 3;
                end case;
            when '1' =>
                mode_inc <= - to_integer(unsigned(reg_img_w_buff));
        end case;
    end process MODE_INC_PROC;

    -- Reset signal for the accelerator
    ACC_RESET_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1' or (curr_state = stTx and next_state = stIdle)) then
                acc_reset <= '1';
            else
                acc_reset <= '0';
            end if;
        end if;
    end process ACC_RESET_PROC;
    
    -- Enable signal for the accelerator
    ACC_ENABLE_PROC: process(curr_state, acc_reset, s_axis_tvalid, m_axis_tready) is
    begin
        case curr_state is
            when stIdle =>
                if (acc_reset = '1') then
                    acc_enable <= '0';
                else
                    acc_enable <= s_axis_tvalid;
                end if;
            when stRx =>
                acc_enable <= s_axis_tvalid;
            when stRxTx =>
                acc_enable <= s_axis_tvalid and m_axis_tready;
            when stTx =>
                acc_enable <= m_axis_tready;
        end case;
    end process ACC_ENABLE_PROC;
    
    -- In case of data loss detection forward a data from buffer
    ACC_DATA_IN_PROC: process (data_in_loss, s_axis_tdata_buff, s_axis_tdata) is
    begin
        if (data_in_loss = '1') then
            acc_data_in <= s_axis_tdata_buff;
        else
            acc_data_in <= s_axis_tdata;
        end if;
    end process ACC_DATA_IN_PROC;
    
    -- Indicating potential input data loss (m_axis_tready falling edge detection)
    DATA_IN_LOSS_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            case curr_state is
                when stRxTx =>
                    if (m_axis_tready_buff = '1' and m_axis_tready = '0' and s_axis_tvalid = '1') then
                        data_in_loss <= '1';
                    elsif (m_axis_tready_buff = '0' and m_axis_tready = '1') then
                        data_in_loss <= '0';
                    end if;
                when others =>
                    data_in_loss <= '0';
            end case;
        end if;
    end process DATA_IN_LOSS_PROC;
    
    -- AXI Stream signals --
    
    -- In case of receiving data at the same time as transmiting s_axis_tready depends on m_axis_tready
    S_AXIS_TREADY_PROC: process(acc_reset, curr_state, m_axis_tready_buff) is
    begin
        case curr_state is
            when stIdle =>
                if (acc_reset = '1') then
                    s_axis_tready <= '0';
                else
                    s_axis_tready <= '1';
                end if;
            when stRx =>
                s_axis_tready <= '1';
            when stRxTx =>
                s_axis_tready <= m_axis_tready_buff;
            when stTx =>
                s_axis_tready <= '0';
        end case;
    end process S_AXIS_TREADY_PROC;
    
    -- In case of transmiting data at the same time as receiving m_axis_tvalid depends on s_axis_tvalid
    M_AXIS_TVALID_PROC: process(curr_state, s_axis_tvalid_buff) is
    begin
        case curr_state is
            when stIdle =>
                m_axis_tvalid <= '0';
            when stRx =>
                m_axis_tvalid <= '0';
            when stRxTx =>
                m_axis_tvalid <= s_axis_tvalid_buff;
            when stTx =>
                m_axis_tvalid <= '1';
        end case;
    end process M_AXIS_TVALID_PROC;
    
    -- Forward output data from the accelerator
    M_AXIS_TDATA_PROC: process (acc_data_out) is
    begin
        m_axis_tdata <= acc_data_out;
    end process M_AXIS_TDATA_PROC;
    
    -- Set m_axis_tlast signal for the last data
    M_AXIS_TLAST_PROC: process(curr_state, next_state) is
    begin
        if (curr_state = stTx and next_state = stIdle) then
            m_axis_tlast <= '1';
        else
            m_axis_tlast <= '0';
        end if;
    end process M_AXIS_TLAST_PROC;
    
    -- Buffers for AXI Stream input signals
    AXIS_BUFF_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then    
                s_axis_tdata_buff  <= (others => '0');
                s_axis_tvalid_buff <= '0';
                s_axis_tlast_buff  <= '0';
                m_axis_tready_buff <= '0';
            else
                if (m_axis_tready_buff = '1') then
                    s_axis_tdata_buff  <= s_axis_tdata;
                end if;
                s_axis_tvalid_buff <= s_axis_tvalid;
                s_axis_tlast_buff  <= s_axis_tlast;
                m_axis_tready_buff <= m_axis_tready;
            end if;
        end if;
    end process AXIS_BUFF_PROC;
    
    -- FSM --
    -- stIdle: idle state
    -- stRx: only receiving data
    -- stRxTx: receiving and transmiting data
    -- stTx (only transmiting data
    
    STATE_TRANSITION: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                curr_state <= stIdle;
            else
                curr_state <= next_state;
            end if;
        end if;
    end process STATE_TRANSITION;
    
    NEXT_STATE_LOGIC: process (curr_state, s_axis_tvalid, m_axis_tready, cnt, cnt_cmp1, cnt_cmp2, cnt_cmp3, reg_ctrl_buff) is
    begin
        next_state <= curr_state;
        case curr_state is
            when stIdle =>
                if (s_axis_tvalid = '1') then
                    if (reg_ctrl_buff(2) =  '1') then
                        next_state <= stRxTx;
                    else
                        next_state <= stRx;
                    end if;
                end if;
            when stRx =>
                if (cnt >= cnt_cmp1) then
                    next_state <= stRxTx;
                end if;
            when stRxTx =>
                if (cnt >= cnt_cmp2) then
                    next_state <= stTx;
                end if;
            when stTx =>
                if (m_axis_tready = '1' and cnt >= cnt_cmp3) then
                    next_state <= stIdle;
                end if;
        end case;
    end process NEXT_STATE_LOGIC;
    
    -- Data flow counter process
    CNT_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (curr_state = stTx and next_state = stIdle) then
                cnt <= 0;
            else
                if (acc_enable = '1') then
                    cnt <= cnt + 1;
                end if;
            end if;
        end if;
    end process CNT_PROC;
    
    -- Calculating intermediate results for comparison to meet timing requirements
    CNT_CMP_VAL_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                cnt_cmp1 <= 0;
                cnt_cmp2 <= 0;
                cnt_cmp3 <= 0;
            else
                cnt_cmp1 <= to_integer(unsigned(reg_img_w_buff)) + mode_inc;
                cnt_cmp2 <= to_integer(unsigned(reg_img_w_buff)) * to_integer(unsigned(reg_img_h_buff)) - 1;
                cnt_cmp3 <= to_integer(unsigned(reg_img_w_buff)) * to_integer(unsigned(reg_img_h_buff)) + to_integer(unsigned(reg_img_w_buff)) + mode_inc;
            end if;
        end if;
    end process CNT_CMP_VAL_PROC;

end architecture rtl; -- of axi_acc_edge_detection