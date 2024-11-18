import React, { useState } from 'react';

import { Row, Col, Table } from 'antd';

import { Container } from '../component';
import Color from '../style/Color';

const RewardHistory = () => {
  const dataSource = [
    {
      key: '1',
      date: '01.02.2024 00:00:00',
      reward: 'Node Referral',
      uptime: '00 Days, 24 Hrs, 60 Min',
      amount: '12,204.20 SP',
      hash: 'db2919sd911123123...de23',
    },
  ];

  const columns = [
    {
      title: 'Date',
      dataIndex: 'date',
      key: 'date',
    },
    {
      title: 'Reward',
      dataIndex: 'reward',
      key: 'reward',
    },
    {
      title: 'Uptime',
      dataIndex: 'uptime',
      key: 'uptime',
    },
    {
      title: 'Amount',
      dataIndex: 'amount',
      key: 'amount',
    },
    {
      title: 'Hash',
      dataIndex: 'hash',
      key: 'hash',
    },
  ];

  return (
    <>
      <Table
        dataSource={dataSource}
        columns={columns}
        pagination={false}
        style={{ backgroundColor: Color.black13, color: Color.yellow }}
      />
      ;
    </>
  );
};

export default RewardHistory;
