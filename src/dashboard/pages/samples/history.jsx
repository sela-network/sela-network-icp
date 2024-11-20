import React from 'react';
import Color from '../../style/Color';
import { Text } from '../../component';

const dataSource = [
  {
    key: '1',
    epoch: 'Epoch 1',
    date: 'DD, MM, YY ~ DD. MM. YY',
    uptime: '00 Days, 24 Hrs, 60 Min',
    nodeRewards: '12,204.20 SP',
    referralRewards: '12,204.20 SP',
    bonusReward: '12,204.20 SP',
  },
  {
    key: '2',
    epoch: 'Epoch 1',
    date: 'DD, MM, YY ~ DD. MM. YY',
    uptime: '00 Days, 24 Hrs, 60 Min',
    nodeRewards: '12,204.20 SP',
    referralRewards: '12,204.20 SP',
    bonusReward: '12,204.20 SP',
  },
];

const renderColumn = ({ text, color = '#fff' }) => {
  return {
    props: {
      style: { background: Color.semiGray },
    },
    children: (
      <div>
        <Text children={text} color={color} size={14} />
      </div>
    ),
  };
};

const columns = [
  {
    title: 'Epoch',
    dataIndex: 'epoch',
    key: 'epoch',
    fixed: 'left',
    render(text) {
      return renderColumn({ text });
    },
  },
  {
    title: 'Start / End Date',
    dataIndex: 'date',
    key: 'date',
    render(text) {
      return renderColumn({ text });
    },
  },
  {
    title: 'Uptime',
    dataIndex: 'uptime',
    key: 'uptime',
    render(text) {
      return renderColumn({ text });
    },
  },
  {
    title: 'Node Rewards',
    dataIndex: 'nodeRewards',
    key: 'nodeRewards',
    render(text) {
      return renderColumn({ text });
    },
  },
  {
    title: 'Referral Rewards',
    dataIndex: 'referralRewards',
    key: 'referralRewards',
    render(text) {
      return renderColumn({ text });
    },
  },
  {
    title: 'Bonus Rewards',
    dataIndex: 'bonusReward',
    key: 'bonusReward',
    render(text) {
      return renderColumn({ text });
    },
  },
];

export { dataSource, columns };
