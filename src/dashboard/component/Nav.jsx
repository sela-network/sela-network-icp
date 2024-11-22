import React from 'react';
import { Layout } from 'antd';
const { Footer, Sider } = Layout;

import { SelaLogo, AppMenu, Spacing, Text } from './index';

const Nav = ({ menuItems, onMenuClick, selectedMenu, onLogout }) => {
  return (
    <Sider width={350} style={{ position: 'fixed', height: '100%', left: 0 }}>
      <SelaLogo />

      <Spacing margin={64} />

      {menuItems.map((item, index) => (
        <div key={index} onClick={() => onMenuClick(item)}>
          <AppMenu
            leftIcon={item.leftIcon}
            text={item.text}
            isActive={selectedMenu.text == item.text}
          />
        </div>
      ))}

      <Spacing margin={32} />

      <div onClick={onLogout}>
        <Text children={'Logout'} />
      </div>
    </Sider>
  );
};

export default Nav;
