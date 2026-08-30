# =============================================================================
#  Toolbox :: WPF layout
# =============================================================================

$XamlA = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Toolbox" Height="760" Width="1180" MinHeight="560" MinWidth="900"
        WindowStartupLocation="CenterScreen" Background="#0F1115"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg"      Color="#0F1115"/>
    <SolidColorBrush x:Key="Panel"   Color="#171A21"/>
    <SolidColorBrush x:Key="Panel2"  Color="#1E222B"/>
    <SolidColorBrush x:Key="Line"    Color="#2A2F3A"/>
    <SolidColorBrush x:Key="Fg"      Color="#E6E9EF"/>
    <SolidColorBrush x:Key="Muted"   Color="#8B93A5"/>
    <SolidColorBrush x:Key="Accent"  Color="#4C8DFF"/>
    <SolidColorBrush x:Key="Danger"  Color="#E05A5A"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="Background" Value="{StaticResource Panel2}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="6" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#2A3040"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Margin" Value="0,3,0,3"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Panel2}"/>
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="CaretBrush" Value="{StaticResource Fg}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>

    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="b" Background="Transparent" BorderThickness="0,0,0,2"
                    BorderBrush="Transparent" Padding="16,9">
              <ContentPresenter ContentSource="Header" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter Property="Foreground" Value="{StaticResource Fg}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="{StaticResource Fg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Expander">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
      <Setter Property="IsExpanded" Value="True"/>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="6,4"/>
    </Style>
  </Window.Resources>
'@

$XamlB = @'
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- ============ header ============ -->
    <Border Grid.Row="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}"
            BorderThickness="0,0,0,1" Padding="18,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center">
          <TextBlock Text="TOOLBOX" FontSize="19" FontWeight="Bold" Foreground="{StaticResource Fg}"/>
          <TextBlock x:Name="SubTitle" FontSize="11" Foreground="{StaticResource Muted}"/>
        </StackPanel>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Preset" VerticalAlignment="Center" Foreground="{StaticResource Muted}" Margin="0,0,8,0"/>
          <ComboBox x:Name="PresetCombo" Width="180" Margin="0,0,10,0"/>
          <Button x:Name="BtnApplyPreset" Content="Select" Style="{StaticResource Btn}" Padding="12,6"/>
          <CheckBox x:Name="HideInstalled" Content="Hide installed" VerticalAlignment="Center"
                    Margin="12,0,4,0" Foreground="{StaticResource Muted}" FontSize="12"/>
          <Grid Width="230" Margin="10,0,0,0">
            <TextBox x:Name="SearchBox"/>
            <TextBlock x:Name="SearchHint" Text="Search..." Foreground="{StaticResource Muted}"
                       Margin="10,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          </Grid>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ============ body ============ -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="3*" MinWidth="420"/>
        <ColumnDefinition Width="4"/>
        <ColumnDefinition Width="2*" MinWidth="280"/>
      </Grid.ColumnDefinitions>

      <TabControl x:Name="Tabs" Grid.Column="0" Background="Transparent" BorderThickness="0" Padding="0">
        <TabItem Header="Apps">
          <DockPanel Margin="14,10,10,10">
            <Border DockPanel.Dock="Bottom" Padding="0,12,0,0">
              <StackPanel Orientation="Horizontal">
                <Button x:Name="BtnInstall"   Content="Install selected"  Style="{StaticResource BtnPrimary}"/>
                <Button x:Name="BtnUninstall" Content="Uninstall selected" Style="{StaticResource Btn}"/>
                <Button x:Name="BtnAppsNone"  Content="Clear"             Style="{StaticResource Btn}"/>
                <TextBlock x:Name="AppsCount" VerticalAlignment="Center" Foreground="{StaticResource Muted}"/>
              </StackPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="AppsPanel"/>
            </ScrollViewer>
          </DockPanel>
        </TabItem>

        <TabItem Header="Tweaks">
          <DockPanel Margin="14,10,10,10">
            <Border DockPanel.Dock="Bottom" Padding="0,12,0,0">
              <StackPanel Orientation="Horizontal">
                <Button x:Name="BtnTweakApply" Content="Apply selected" Style="{StaticResource BtnPrimary}"/>
                <Button x:Name="BtnTweakUndo"  Content="Undo selected"  Style="{StaticResource Btn}"/>
                <Button x:Name="BtnTweaksNone" Content="Clear"          Style="{StaticResource Btn}"/>
                <TextBlock x:Name="TweaksCount" VerticalAlignment="Center" Foreground="{StaticResource Muted}"/>
              </StackPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="TweaksPanel"/>
            </ScrollViewer>
          </DockPanel>
        </TabItem>

        <TabItem Header="Scripts">
          <DockPanel Margin="14,10,10,10">
            <Border DockPanel.Dock="Bottom" Padding="0,12,0,0">
              <StackPanel Orientation="Horizontal">
                <Button x:Name="BtnRunScripts"  Content="Run selected" Style="{StaticResource BtnPrimary}"/>
                <Button x:Name="BtnScriptsNone" Content="Clear"        Style="{StaticResource Btn}"/>
                <TextBlock x:Name="ScriptsCount" VerticalAlignment="Center" Foreground="{StaticResource Muted}"/>
              </StackPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="ScriptsPanel"/>
            </ScrollViewer>
          </DockPanel>
        </TabItem>
      </TabControl>
'@

$XamlC = @'
      <GridSplitter Grid.Column="1" Width="4" HorizontalAlignment="Stretch"
                    Background="{StaticResource Line}"/>

      <DockPanel Grid.Column="2" Background="{StaticResource Panel}" Margin="0">
        <Border DockPanel.Dock="Top" Padding="14,10" BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1">
          <Grid>
            <TextBlock Text="OUTPUT" FontSize="11" FontWeight="SemiBold"
                       Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
            <Button x:Name="BtnClearLog" Content="Clear" Style="{StaticResource Btn}"
                    HorizontalAlignment="Right" Padding="10,3" Margin="0" FontSize="11"/>
          </Grid>
        </Border>
        <RichTextBox x:Name="LogBox" Background="{StaticResource Bg}" Foreground="{StaticResource Fg}"
                     BorderThickness="0" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                     Padding="12,8"/>
      </DockPanel>
    </Grid>

    <!-- ============ footer ============ -->
    <Border Grid.Row="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}"
            BorderThickness="0,1,0,0" Padding="18,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center">
          <TextBlock x:Name="StatusText" Text="Ready" FontSize="12" Foreground="{StaticResource Muted}"/>
          <ProgressBar x:Name="Bar" Height="4" Margin="0,6,20,0" Minimum="0" Maximum="100" Value="0"
                       Background="{StaticResource Panel2}" Foreground="{StaticResource Accent}"
                       BorderThickness="0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource Btn}" IsEnabled="False"/>
          <Button x:Name="BtnClose"  Content="Close"  Style="{StaticResource Btn}" Margin="0"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$Xaml = $XamlA + $XamlB + $XamlC
