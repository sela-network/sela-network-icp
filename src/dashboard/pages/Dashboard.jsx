import React from 'react';

import { Container, Text, Row, Column, Icon } from '../component';
import StackedChart from './charts/StackedChart';

import { Button } from 'antd';
import Color from '../style/Color';

const Dashboard = ({ handleMoreClick }) => {
  const BalanceContainer = ({ title, value, flex }) => {
    return (
      <Container alignItems="center" spacing={8} flex={flex}>
        <Text children={title} weight="semiBold" size={16} />
        <Row spacing={8} flexWrap="nowrap">
          <Icon
            name="sela"
            fillColor={Color.yellow}
            style={{ width: 20, height: 20 }}
            backgroundColor="#000"
            borderColor={Color.border}
          />
          <Text children={value} weight="semiBold" size={24} />
        </Row>
        <Text children="Uptime: D:00 H:00 M:00" size={14} />
      </Container>
    );
  };

  const ChartContainer = () => {
    return (
      <Container>
        <Text children="Reward Statistics" weight="semiBold" size={16} />
        <Row justifyContent="space-between">
          <Text
            children="This graph shows the total sum of node participation and referral and mission rewards."
            size={14}
          />
          <Button
            shape="round"
            size={20}
            style={{
              backgroundColor: Color.yellow,
              borderColor: Color.yellow,
              width: 66,
              height: 26,
            }}
            onClick={handleMoreClick}
          >
            <Text children="More" size={14} weight="semiBold" color="#000" />
          </Button>
        </Row>
        <StackedChart />
      </Container>
    );
  };

  const ContainerStatus = () => {
    return (
      <Container>
        <Row justifyContent="space-between">
          <Row spacing={8} flexWrap="nowrap">
            <Icon name="phone" style={{ width: 20, height: 20 }} />
            <Text children="Application Connect" weight="semiBold" size={14} />
          </Row>
          <Button
            shape="round"
            size={16}
            style={{
              backgroundColor: Color.green,
              borderColor: Color.green,
            }}
          >
            <Text
              children={'Connected'}
              size={16}
              weight="semiBold"
              color="#000"
            />
          </Button>
        </Row>
        <Button
          shape="round"
          size={16}
          style={{
            backgroundColor: Color.black13,
            borderColor: Color.green,
          }}
        >
          <Text
            children={'Network Quality: 100%'}
            size={16}
            weight="semiBold"
            color={Color.green}
          />
        </Button>
      </Container>
    );
  };

  return (
    <>
      <Row alignItems="start">
        <Column flex={5}>
          <Row>
            <BalanceContainer
              title="Total Balance"
              value="100,000,000.00"
              flex={2}
            />
            <BalanceContainer title="1 Epoch Earnings" value="100,000,000.00" />
            <BalanceContainer title="Today's Earnings" value="100,000,000.00" />
          </Row>
          <ChartContainer />
        </Column>
        <Column flex={2} backgroundColor="red">
          <ContainerStatus />
        </Column>
      </Row>
    </>
  );
};

export default Dashboard;
