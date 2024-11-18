import React from 'react';
import { Space } from 'antd';

import Icon from './Icon';

const AppMenu = ({ leftIcon, text }) => {
  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        width: '100%',
        marginBottom: '32px',
      }}
    >
      <Space>
        <Icon name={leftIcon} />
        <span style={{ color: '#fff', fontSize: 18 }}>{text}</span>
      </Space>
      <Icon
        name="arrowRight"
        backgroundColor="#131313"
        style={{ width: 16, height: 16 }}
      />
    </div>
  );
};

export default AppMenu;
