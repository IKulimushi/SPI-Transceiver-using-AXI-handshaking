library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity SPI_master_tb is
end entity SPI_master_tb;

architecture sim of SPI_master_tb is

    constant c_idle_bit         : std_logic := '0'; -- idle bit value
    constant c_dummy_bits       : natural   := 8;   -- number of dummy bits to be transmitted before the data bits
    constant c_data_bits        : natural   := 8;   -- number of data bits to be transmitted
    constant c_chip_num         : positive  := 4;     -- number of chip selects
    constant c_baud_rate        : natural   := 9600;  -- baud rate
    constant c_system_clk_freq  : natural   := 100e6; -- system clock frequency in Hz
    constant c_clk_period       : time      := 10 ns; -- 100 MHz clock

    signal clk                  : std_logic := '0';
    signal rst                  : std_logic := '1';
    signal tx_byte              : std_logic_vector((c_data_bits-1) downto 0);
    signal cs_switch            : std_logic_vector(c_chip_num downto 1) := (others => '1');
    signal cs_switch_out        : std_logic_vector(c_chip_num downto 1);
    signal cpol                 : std_logic := '0';
    signal cpha                 : std_logic := '0';
    signal rx_ready             : std_logic := '0';
    signal tx_valid             : std_logic;
    signal tx_last              : std_logic;
    signal mosi                 : std_logic;
    signal tx_ready             : std_logic;
    signal rx_valid             : std_logic := '0';
    signal rx_last              : std_logic := '0';
    signal miso                 : std_logic := c_idle_bit;
    signal miso_shr_tb          : std_logic_vector(tx_byte'range);
    signal sclk                 : std_logic;
    signal rx_byte              : std_logic_vector(7 downto 0);
    signal i_tracker            : natural := 0;
    signal data_bits            : natural := c_data_bits;
    -- alias <name> is << signal <hierarchical_path> : <type> >>;
    alias M_S_EDGE is << signal .spi_master_tb.UUT.master_sample_edge : std_logic >>;

begin

    clk <= not clk after (c_clk_period/2); -- 100 MHz clock

    stim: process
        variable v_tracker : natural := 0; 
        variable v_miso_shr_tb: std_logic_vector(tx_byte'range):= (others => '0');
    begin
        --======================================================================
        -- MASTER IS IN IDLE STATE 
        --======================================================================
        -- deassert rst after 100 ns
        miso_shr_tb <= (others => c_idle_bit);
        wait for 100 ns;

        rst     <= '0';
        rx_last <= '0';
        
        -- configure the SPI master to transmit data with => mode 0 : CPOL = 0 and CPHA = 0 (works correctly), mode 1 : CPOL = 0 and CPHA = 1 (blank), mode 2 : CPOL = 1 and CPHA = 0 (blank), mode 3 : CPOL = 1 and CPHA = 1 (blank)
        cpol    <= '0';
        cpha    <= '0';
        tx_byte <= x"CB"; -- send a byte of data to the master  MSB 1100 1011 LSB

        for i in 1 to 10e4 loop
            wait for c_clk_period;
        end loop;

        cs_switch <= "1110"; -- set the chip select 1 to active
        wait for c_clk_period;

        rx_ready <= '1'; -- indicate that the slave is ready to receive data
        rx_valid <= '1'; -- indicate that the slave data on the MISO line is valid for master to sample
        
        --======================================================================
        -- MASTER IS IN TRANSMIT AND SAMPLING STATE
        --======================================================================
        --======================================================================
        -- MASTER IS TRANSMITTING MOSI BITS AND SAMPLING DUMMY MISO BITS
        --======================================================================
        wait until rising_edge(M_S_EDGE); -- dummy sample 0 no data has been trasnmitted therefore nothing should be sampled yet
        i_tracker   <= 0;
        miso        <= c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- dummy sample 1
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 2
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 3
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 4
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 5
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 6
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 7
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        wait until rising_edge(M_S_EDGE); -- dummy sample 8
        i_tracker   <= i_tracker + 1;
        miso        <= c_idle_bit;
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & mosi;
        --======================================================================
        -- MASTER FINISHED TRANSMITTING MOSI BITS AND SAMPLING DUMMY MISO BITS
        --======================================================================

        --======================================================================
        -- MASTER IS SAPMPLING VALID MISO BITS
        --======================================================================
        wait until rising_edge(M_S_EDGE); -- valid sample 1
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 2
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 3
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 4
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 5
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 6
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 7
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;
        wait until rising_edge(M_S_EDGE); -- valid sample 8
        i_tracker   <= i_tracker + 1;
        miso        <= miso_shr_tb((miso_shr_tb'left));
        miso_shr_tb <= miso_shr_tb((miso_shr_tb'left)-1 downto 0) & c_idle_bit;

        wait until rising_edge(M_S_EDGE); -- all bits sampled, wait for the next rising edge of the master sample edge to indicate that the master has finished sampling all bits
        --======================================================================
        -- MASTER FINISHED SAMPLING VALID MISO BITS
        --======================================================================

        tx_byte <= (others => c_idle_bit);
        rx_last <= '1';
        miso    <= c_idle_bit;

        wait for c_clk_period;

        rx_last   <= '0';
        rx_valid  <= '0';
        cs_switch <= (others => '1');

        for i in 1 to 10e4 loop
            wait for c_clk_period;
        end loop;

        stop;
    end process stim;

    UUT: entity work.SPI_master
    generic map(
        G_DUMMY_BITS => c_dummy_bits,
        G_DATA_BITS  => c_data_bits,
        G_CHIP_NUM   => c_chip_num,
        G_SYSTEM_CLK_FREQ => c_system_clk_freq,
        G_BAUD_RATE  => c_baud_rate,
        G_IDLE_BIT   => c_idle_bit
    )
    port map(
        I_CLK       => clk,
        I_ASYNC_RST => rst,
        I_TX_BYTE   => tx_byte,
        I_CS_SWITCH => cs_switch,
        I_CPOL      => cpol,
        I_CPHA      => cpha,

        --master to slave
        I_RX_READY => rx_ready,
        O_TX_VALID => tx_valid,
        O_TX_LAST  => tx_last,
        O_MOSI     => mosi,

        --slave to master
        O_TX_READY => tx_ready,
        I_RX_VALID => rx_valid,
        I_RX_LAST  => rx_last,
        I_MISO     => miso,

        O_SCLK      => sclk,
        O_CS_SWITCH => cs_switch_out,
        O_RX_BYTE   => rx_byte
        
    );
    

end architecture;
