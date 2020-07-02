import * as React from 'react';
import styled from 'styled-components';
import { colors } from '../../config.json';
import { TunnelState } from '../../shared/daemon-rpc-types';
import { messages } from '../../shared/gettext';
import ConnectionPanelContainer from '../containers/ConnectionPanelContainer';
import * as AppButton from './AppButton';
import ImageView from './ImageView';
import Marquee from './Marquee';
import { MultiButton } from './MultiButton';
import SecuredLabel, { SecuredDisplayStyle } from './SecuredLabel';

interface ITunnelControlProps {
  tunnelState: TunnelState;
  blockWhenDisconnected: boolean;
  selectedRelayName: string;
  city?: string;
  country?: string;
  onConnect: () => void;
  onDisconnect: () => void;
  onReconnect: () => void;
  onSelectLocation: () => void;
}

const SwitchLocationButton = styled(AppButton.TransparentButton)({
  marginBottom: 16,
});

const Secured = styled(SecuredLabel)({
  fontFamily: 'Open Sans',
  fontSize: '16px',
  fontWeight: 800,
  lineHeight: '22px',
  marginBottom: '2px',
});

const Footer = styled.div({
  display: 'flex',
  flexDirection: 'column',
  flex: 0,
  paddingBottom: '16px',
  paddingLeft: '24px',
  paddingRight: '24px',
});

const Body = styled.div({
  display: 'flex',
  flexDirection: 'column',
  padding: '0 24px',
  marginTop: '176px',
  flex: 1,
});

const Wrapper = styled.div({
  display: 'flex',
  flexDirection: 'column',
  flex: 1,
});

const Location = styled.div({
  display: 'flex',
  flexDirection: 'column',
  marginBottom: 2,
});

const StyledMarquee = styled(Marquee)({
  fontFamily: 'DINPro',
  fontSize: '34px',
  lineHeight: '38px',
  fontWeight: 900,
  overflow: 'hidden',
  color: colors.white,
});

export default class TunnelControl extends React.Component<ITunnelControlProps> {
  public render() {
    const SwitchLocation = () => {
      return (
        <SwitchLocationButton onClick={this.props.onSelectLocation}>
          {messages.pgettext('tunnel-control', 'Switch location')}
        </SwitchLocationButton>
      );
    };

    const SelectedLocation = () => (
      <SwitchLocationButton onClick={this.props.onSelectLocation}>
        <AppButton.Label>{this.props.selectedRelayName}</AppButton.Label>
        <AppButton.Icon height={12} width={7} source="icon-chevron" />
      </SwitchLocationButton>
    );

    const Connect = () => (
      <AppButton.GreenButton onClick={this.props.onConnect}>
        {messages.pgettext('tunnel-control', 'Secure my connection')}
      </AppButton.GreenButton>
    );

    const Disconnect = (props: React.ComponentProps<typeof AppButton.RedTransparentButton>) => (
      <AppButton.RedTransparentButton onClick={this.props.onDisconnect} {...props}>
        {messages.pgettext('tunnel-control', 'Disconnect')}
      </AppButton.RedTransparentButton>
    );

    const Cancel = (props: React.ComponentProps<typeof AppButton.RedTransparentButton>) => (
      <AppButton.RedTransparentButton onClick={this.props.onDisconnect} {...props}>
        {messages.pgettext('tunnel-control', 'Cancel')}
      </AppButton.RedTransparentButton>
    );

    const Dismiss = (props: React.ComponentProps<typeof AppButton.RedTransparentButton>) => (
      <AppButton.RedTransparentButton onClick={this.props.onDisconnect} {...props}>
        {messages.pgettext('tunnel-control', 'Dismiss')}
      </AppButton.RedTransparentButton>
    );

    const Reconnect = (props: React.ComponentProps<typeof AppButton.RedTransparentButton>) => (
      <AppButton.RedTransparentButton onClick={this.props.onReconnect} {...props}>
        <ImageView height={22} width={22} source="icon-reload" tintColor="white" />
      </AppButton.RedTransparentButton>
    );

    let state = this.props.tunnelState.state;

    switch (this.props.tunnelState.state) {
      case 'disconnecting':
        switch (this.props.tunnelState.details) {
          case 'block':
            state = 'error';
            break;
          case 'reconnect':
            state = 'connecting';
            break;
          default:
            state = 'disconnecting';
            break;
        }
        break;
    }

    switch (state) {
      case 'connecting':
        return (
          <Wrapper>
            <Body>
              <Secured displayStyle={SecuredDisplayStyle.securing} />
              <Location>
                {this.renderCity()}
                {this.renderCountry()}
              </Location>
              <ConnectionPanelContainer />
            </Body>
            <Footer>
              <SwitchLocation />
              <MultiButton mainButton={Cancel} sideButton={Reconnect} />
            </Footer>
          </Wrapper>
        );
      case 'connected':
        return (
          <Wrapper>
            <Body>
              <Secured displayStyle={SecuredDisplayStyle.secured} />
              <Location>
                {this.renderCity()}
                {this.renderCountry()}
              </Location>
              <ConnectionPanelContainer />
            </Body>
            <Footer>
              <SwitchLocation />
              <MultiButton mainButton={Disconnect} sideButton={Reconnect} />
            </Footer>
          </Wrapper>
        );

      case 'error':
        if (
          this.props.tunnelState.state === 'error' &&
          !this.props.tunnelState.details.isBlocking
        ) {
          return (
            <Wrapper>
              <Body>
                <Secured displayStyle={SecuredDisplayStyle.failedToSecure} />
              </Body>
              <Footer>
                <SwitchLocation />
                <MultiButton mainButton={Dismiss} sideButton={Reconnect} />
              </Footer>
            </Wrapper>
          );
        } else {
          return (
            <Wrapper>
              <Body>
                <Secured displayStyle={SecuredDisplayStyle.blocked} />
              </Body>
              <Footer>
                <SwitchLocation />
                <MultiButton mainButton={Cancel} sideButton={Reconnect} />
              </Footer>
            </Wrapper>
          );
        }

      case 'disconnecting':
        return (
          <Wrapper>
            <Body>
              <Secured displayStyle={SecuredDisplayStyle.secured} />
              <Location>{this.renderCountry()}</Location>
            </Body>
            <Footer>
              <SelectedLocation />
              <Connect />
            </Footer>
          </Wrapper>
        );

      case 'disconnected': {
        const displayStyle = this.props.blockWhenDisconnected
          ? SecuredDisplayStyle.blocked
          : SecuredDisplayStyle.unsecured;
        return (
          <Wrapper>
            <Body>
              <Secured displayStyle={displayStyle} />
              <Location>{this.renderCountry()}</Location>
            </Body>
            <Footer>
              <SelectedLocation />
              <Connect />
            </Footer>
          </Wrapper>
        );
      }

      default:
        throw new Error(`Unknown TunnelState: ${this.props.tunnelState}`);
    }
  }

  private renderCity() {
    return <StyledMarquee>{this.props.city}</StyledMarquee>;
  }

  private renderCountry() {
    return <StyledMarquee>{this.props.country}</StyledMarquee>;
  }
}
