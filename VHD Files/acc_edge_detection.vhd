library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity acc_edge_detection is
    generic (
		G_DATA_WIDTH      : natural := 8;
		G_MAX_BUFF_LENGTH : natural := 512;
		G_REG_WIDTH       : natural := 16
	);
    Port ( 
        clk    : in std_logic;   -- Clock
        reset  : in std_logic;   -- Reset counters
        enable : in std_logic;   -- Enable data flow
        
        img_w    : in std_logic_vector(G_REG_WIDTH-1 downto 0);     -- Image width
        img_h    : in std_logic_vector(G_REG_WIDTH-1 downto 0);     -- Image height
        mode     : in std_logic_vector(1 downto 0);                 -- Module operation mode 
        edge_thr : in std_logic_vector(7 downto 0);                 -- Edge threshold
        border   : in std_logic;                                    -- Border parameter
        bypass   : in std_logic;                                    -- Bypassing calculations
        
        data_in  : in std_logic_vector(G_DATA_WIDTH-1 downto 0);    -- Input data
        data_out : out std_logic_vector(G_DATA_WIDTH-1 downto 0)    -- Output data
    );
end entity acc_edge_detection;

architecture rtl of acc_edge_detection is
    signal buff_line_0_data_out : std_logic_vector(G_DATA_WIDTH-1 downto 0);    -- Output data from first buffer
    signal buff_line_1_data_out : std_logic_vector(G_DATA_WIDTH-1 downto 0);    -- Output data from second buffer
    
    type data_regs is array (0 to 8) of std_logic_vector(G_DATA_WIDTH-1 downto 0);
    signal data_reg : data_regs;    -- Data registers
    
    signal grad_h : integer;   -- Horizontal gradient
    signal grad_v : integer;   -- Vertical gradient
    signal grad_m : natural;   -- Magnitude gradient
    signal edge   : natural;   -- Edge (pixel value)
    
    signal img_w_p2 : natural;   -- img_w + 2 for comparing
    signal img_w_m1 : natural;   -- img_w - 1 for comparing
    signal img_h_m1 : natural;   -- img_h - 1 for comparing
    
    signal r   : natural;   -- row counter
    signal c   : natural;   -- column counter
    signal cnt : natural;   -- counter
    
    -- Debug
    attribute mark_debug : string;
    attribute mark_debug of grad_h   : signal is "true";
    attribute mark_debug of grad_v   : signal is "true";
    attribute mark_debug of grad_m   : signal is "true";
    attribute mark_debug of edge     : signal is "true";
    attribute mark_debug of data_reg : signal is "true";
    attribute mark_debug of r        : signal is "true";
    attribute mark_debug of c        : signal is "true";
    
begin
    -- 1st data buffer
    BUFF_LINE_0 : entity work.shift_reg(rtl)
        generic map (
            G_DATA_WIDTH      => G_DATA_WIDTH,
            G_REG_WIDTH       => G_REG_WIDTH,
            G_SHIFT_REG_WIDTH => G_MAX_BUFF_LENGTH
        )
        port map (
            clk          => clk,
            reset        => reset,
            shift_en     => enable,
            active_width => img_w,
            data_in      => data_in,
            data_out     => buff_line_0_data_out
        );
    
    -- 2nd data buffer
    BUFF_LINE_1 : entity work.shift_reg(rtl)
        generic map (
            G_DATA_WIDTH      => G_DATA_WIDTH,
            G_REG_WIDTH       => G_REG_WIDTH,
            G_SHIFT_REG_WIDTH => G_MAX_BUFF_LENGTH
        )
        port map (
            clk          => clk,
            reset        => reset,
            shift_en     => enable,
            active_width => img_w,
            data_in      => buff_line_0_data_out,
            data_out     => buff_line_1_data_out
        );
        
    -- Data registers
    REG_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (enable = '1') then
                data_reg(0) <= data_in;
                data_reg(1) <= data_reg(0);
                data_reg(2) <= data_reg(1);
                data_reg(3) <= buff_line_0_data_out;
                data_reg(4) <= data_reg(3);
                data_reg(5) <= data_reg(4);
                data_reg(6) <= buff_line_1_data_out;
                data_reg(7) <= data_reg(6);
                data_reg(8) <= data_reg(7);
            end if;
        end if;
    end process REG_PROC;
    
    -- Horizontal gradient calculation
    GRAD_H_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (enable = '1') then
                if (c = 0) then
                    case border is
                        when '0' =>
                            grad_h <= to_integer(unsigned(data_reg(3))) / 2;
                        when '1' =>
                            grad_h <= (to_integer(unsigned(data_reg(3))) - to_integer(unsigned(data_reg(4)))) / 2;
                    end case;
                elsif (c = img_w_m1) then
                    case border is
                        when '0' =>
                            grad_h <= - to_integer(unsigned(data_reg(5))) / 2;
                        when '1' =>
                            grad_h <= (to_integer(unsigned(data_reg(4))) - to_integer(unsigned(data_reg(5)))) / 2;
                    end case;
                else
                    grad_h <= (to_integer(unsigned(data_reg(3))) - to_integer(unsigned(data_reg(5)))) / 2;
                end if;
            end if;
        end if;
    end process GRAD_H_PROC;
    
    -- Vertical gradient calculation
    GRAD_V_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (enable = '1') then
                if (r = 0) then
                    case border is
                        when '0' => 
                            grad_v <= to_integer(unsigned(data_reg(1))) / 2;
                        when '1' =>
                            grad_v <= (to_integer(unsigned(data_reg(1))) - to_integer(unsigned(data_reg(4)))) / 2;
                    end case;
                elsif (r = img_h_m1) then
                    case border is
                        when '0' =>
                            grad_v <= - to_integer(unsigned(data_reg(7))) / 2;
                        when '1' =>
                            grad_v <= (to_integer(unsigned(data_reg(4))) - to_integer(unsigned(data_reg(7)))) / 2;
                    end case;
                else
                    grad_v <= (to_integer(unsigned(data_reg(1))) - to_integer(unsigned(data_reg(7)))) / 2;
                end if;
            end if;
        end if;
    end process GRAD_V_PROC;
    
    -- Magnitude gradient calculation
    GRAD_M_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (enable = '1') then
                grad_m <= abs(grad_h) + abs(grad_v);
            end if;
        end if;
    end process GRAD_M_PROC;
    
    -- Edge calculation
    EDGE_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (enable = '1') then
                if (grad_m < unsigned(edge_thr)) then
                    edge <= 0;
                else
                    edge <= 255;
                end if;
            end if;
        end if;
    end process EDGE_PROC;

    -- Selecting the output data depending on the bypass and mode
    OUTPUT_PROC: process (grad_h, grad_v, grad_m, edge, bypass, mode, data_reg(0)) is
    begin
        case bypass is
            when '0' =>
                case mode is
                    when "00" =>
                        data_out <= std_logic_vector(to_unsigned(edge, data_out'length));
                    when "01" =>
                        data_out <= std_logic_vector(to_signed(grad_h, data_out'length));
                    when "10" =>
                        data_out <= std_logic_vector(to_signed(grad_v, data_out'length));
                    when "11" =>
                        data_out <= std_logic_vector(to_unsigned(grad_m, data_out'length));
                end case;
            when '1' =>
                data_out <= data_reg(0);
        end case;
    end process OUTPUT_PROC;
    
    -- Counter of received data
    CNT_PROC: process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                cnt <= 0;
            else
                if (enable = '1') then
                    cnt <= cnt + 1;
                end if;
            end if;
        end if;
    end process CNT_PROC;
    
    -- Counting of processed data by rows and columns
    R_C_CNT_PROC: process (clk) is
    begin
        if(rising_edge(clk)) then
            if (reset = '1') then
                r <= 0;
                c <= 0;
            else
                if (enable = '1' and (cnt >= img_w_p2)) then
                    if (c < img_w_m1) then
                        r <= r;
                        c <= c + 1;
                    else
                        r <= r + 1;
                        c <= 0;
                    end if;
                else
                    r <= r;
                    c <= c;
                end if;
            end if;
        end if;
    end process R_C_CNT_PROC;
    
    -- Calculating intermediate results for comparison to meet timing requirements
    CMP_VALS_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                img_w_p2 <= 0;
                img_w_m1 <= 0;
                img_h_m1 <= 0;
            else
                img_w_p2 <= to_integer(unsigned(img_w)) + 2;
                img_w_m1 <= to_integer(unsigned(img_w)) - 1;
                img_h_m1 <= to_integer(unsigned(img_h)) - 1;
            end if;
        end if;
    end process CMP_VALS_PROC;
    
end architecture rtl; -- of acc_edge_detection